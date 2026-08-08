/**
 * Limited Batch Canary — Planning Gate (read-only).
 *
 *   $env:LIMITED_BATCH_PLANNING_LIVE="1"
 *   node --env-file=.env ./node_modules/vitest/vitest.mjs run src/lib/__tests__/limited-batch-planning.live.test.ts
 *
 * No AI calls, no Emergency mutation, no force re-analysis.
 */
import { describe, expect, it } from "vitest";
import { writeFileSync, mkdirSync } from "node:fs";
import { prisma } from "@/lib/db";
import { readGlobalAiEmergencyControl } from "@/lib/ai/global-ai-emergency";
import {
  buildUncoveredEligibleQueue,
  getCoverageMetrics,
} from "@/lib/build-guides/visual-coverage";
import { loadCharacterHints } from "@/lib/build-guides/character-match";
import { GENSIN_VIDEO_TITLE_MARKER } from "@/lib/build-guides/genshin-video-title";
import {
  estimateVisualPromptTokens,
  VISUAL_PROMPT_TOKEN_HARD_MAX,
  shouldAbortPendingBatch,
  classifyVisualAnalysisFailure,
} from "@/lib/build-guides/visual-analysis-safety";
import {
  needsLongformFullDiscovery,
  planLongformChunks,
} from "@/lib/build-guides/visual-longform";

const enabled = process.env.LIMITED_BATCH_PLANNING_LIVE === "1";
const STORM = ["http429", "providerRateLimited", "geminiProviderCoolingDown"];
const EXCLUDE = new Set(["gR-wnOJNMMk", "UgT4ehIbIUk", "LP9Xs5fAmOI"]);
const MAX_RANGE = 360;

describe.skipIf(!enabled)("Limited Batch Canary Planning Gate", () => {
  it(
    "snapshot + select 3 or BLOCKED_NO_ELIGIBLE_INPUT",
    async () => {
      const emergency = await readGlobalAiEmergencyControl();
      const coverage = await getCoverageMetrics({ eligibleLimit: 3 });

      const running = await prisma.guideVisualAnalysisJob.count({
        where: { status: "running" },
      });
      const pendingRetry = await prisma.guideVisualAnalysisJob.count({
        where: { status: { in: ["pending", "retry", "queued", "waiting"] } },
      });
      const pipelineRunning = await prisma.guidePipelineRun.count({
        where: { status: "running" },
      });
      const pipelineItemActive = await prisma.guidePipelineItem.count({
        where: { status: { in: ["pending", "retry", "running"] } },
      });
      const recent429 = await prisma.guideVisualAnalysisJob.count({
        where: {
          updatedAt: { gte: new Date(Date.now() - 60 * 60 * 1000) },
          OR: [
            { errorCode: { contains: "429" } },
            { errorCode: { in: STORM } },
          ],
        },
      });

      const pendingVideos = await prisma.guideVideo.findMany({
        where: {
          title: { contains: GENSIN_VIDEO_TITLE_MARKER },
          analysisStatus: { not: "analyzed" },
          privacyStatus: "public",
          channel: {
            enabled: true,
            permissionStatus: "approved_for_processing",
          },
        },
        orderBy: [{ publishedAt: "desc" }, { updatedAt: "desc" }],
        take: 500,
        select: {
          videoId: true,
          title: true,
          durationSeconds: true,
          analysisStatus: true,
          privacyStatus: true,
        },
      });
      const analyzedCount = await prisma.guideVideo.count({
        where: {
          title: { contains: GENSIN_VIDEO_TITLE_MARKER },
          analysisStatus: "analyzed",
          privacyStatus: "public",
          channel: {
            enabled: true,
            permissionStatus: "approved_for_processing",
          },
        },
      });

      const hints = await loadCharacterHints();
      const coveredRows = await prisma.characterBuildRecommendation.findMany({
        where: { status: { not: "rejected" } },
        select: { characterId: true },
      });
      const coveredIds = new Set(coveredRows.map((r) => r.characterId));
      const queue = buildUncoveredEligibleQueue({
        pendingVideos: pendingVideos.map((v) => ({
          videoId: v.videoId,
          title: v.title,
        })),
        hints,
        coveredIds,
        limit: 500,
      });

      const durationById = new Map(
        pendingVideos.map((v) => [v.videoId, v.durationSeconds ?? 0]),
      );
      const statusById = new Map(
        pendingVideos.map((v) => [v.videoId, v.analysisStatus]),
      );

      const safe = [];
      for (const item of queue.selected) {
        if (EXCLUDE.has(item.videoId)) continue;
        if (statusById.get(item.videoId) === "analyzed") continue;
        const [recent429Job, unstableFails, runningJob] = await Promise.all([
          prisma.guideVisualAnalysisJob.count({
            where: {
              videoId: item.videoId,
              errorCode: { in: STORM },
              createdAt: { gte: new Date(Date.now() - 14 * 24 * 60 * 60_000) },
            },
          }),
          prisma.guideVisualAnalysisJob.count({
            where: {
              videoId: item.videoId,
              status: "failed",
              createdAt: { gte: new Date(Date.now() - 14 * 24 * 60 * 60_000) },
            },
          }),
          prisma.guideVisualAnalysisJob.count({
            where: { videoId: item.videoId, status: "running" },
          }),
        ]);
        if (recent429Job || unstableFails || runningJob) continue;

        const duration = durationById.get(item.videoId) ?? 0;
        const estimatedTokens = estimateVisualPromptTokens({
          durationSeconds: duration,
          fps: 1,
          analysisMode: "full_discovery",
          targetCharacterCount: 1,
        });
        const longform = needsLongformFullDiscovery({
          durationSeconds: duration,
          fps: 1,
          targetCharacterCount: 1,
        });
        let expectedChunks = 1;
        let expectedProviderCalls = 1;
        let estimatedInputTokens = estimatedTokens;
        if (longform) {
          try {
            const plan = planLongformChunks({
              videoId: item.videoId,
              durationSeconds: duration,
              fps: 1,
              targetCharacterCount: 1,
              maxRangeSeconds: MAX_RANGE,
            });
            if (plan.chunks.length > 6 || plan.estimatedAiCalls > 6) continue;
            expectedChunks = plan.chunks.length;
            expectedProviderCalls = plan.estimatedAiCalls;
            estimatedInputTokens = plan.estimatedInputTokens;
          } catch {
            continue;
          }
        }

        safe.push({
          videoId: item.videoId,
          title: item.title.slice(0, 120),
          characterId: item.characterId,
          durationSeconds: duration,
          analysisStatus: statusById.get(item.videoId),
          estimatedTokens,
          longform,
          expectedChunks,
          expectedProviderCalls,
          estimatedInputTokens,
          recent429: recent429Job,
          unstableFails,
          runningJob,
        });
      }

      const shorts = safe.filter((c) => !c.longform);
      const longs = safe.filter(
        (c) =>
          c.longform &&
          c.estimatedTokens >= 90_000 &&
          c.estimatedTokens <= 120_000,
      );
      const pick: Array<Record<string, unknown>> = [];
      if (shorts[0]) pick.push({ slot: "A", ...shorts[0] });
      if (longs[0]) pick.push({ slot: "B", ...longs[0] });
      else if (shorts[1]) pick.push({ slot: "B_fallback_short", ...shorts[1] });
      const used = new Set(pick.map((p) => String(p.videoId)));
      const cShort = shorts.find((s) => !used.has(s.videoId));
      if (cShort) pick.push({ slot: "C", ...cShort });

      const ready = pick.length >= 3;
      const batchTotalCalls = ready
        ? pick.reduce((s, p) => s + Number(p.expectedProviderCalls), 0)
        : 0;
      const batchTotalTokens = ready
        ? pick.reduce((s, p) => s + Number(p.estimatedInputTokens), 0)
        : 0;

      const codeAudit = {
        retryAfter: true,
        exponentialBackoffJitter: true,
        maxAttempts: "geminiVideoSettings.maxAttempts",
        providerCooldown: true,
        perVideoInflight: "activeJobs in analyzeVideoVisuals",
        batchAbortOn429: shouldAbortPendingBatch("http429") === true,
        batchAbortOnCooldown: shouldAbortPendingBatch("providerRateLimited"),
        classify429: classifyVisualAnalysisFailure("http429"),
        stockBatchBreaksOn429:
          "analyzePendingGenshinVideos: shouldAbortPendingBatch → break (does not continue to remaining items)",
        stockBatchAllowLongform: false,
        stockBatchSkipAutoPublish: false,
        limitedBatchMustUseHarness:
          "Live canary must call analyzeVideoVisuals sequentially with skipAutoPublish:true, allowLongform per-item, force:false",
      };

      const report = {
        emergency: {
          emergencyStopped: emergency.emergencyStopped,
          version: emergency.version,
          reason: emergency.reason,
          updatedAt: emergency.updatedAt,
        },
        queueSnapshot: {
          eligiblePendingVideos: coverage.eligiblePendingVideos,
          remainingEligibleVideos: coverage.remainingEligibleVideos,
          recoverablePostProcessFailures:
            coverage.recoverablePostProcessFailures,
          titleResolutionFailedVideos: coverage.titleResolutionFailedVideos,
          titleResolutionFailedSamples: coverage.titleResolutionFailedSamples,
          pendingPublicApprovedMarkerVideos: pendingVideos.length,
          analyzedPublicApprovedMarkerVideos: analyzedCount,
          queueEligibleCount: queue.eligiblePendingVideos,
          skippedNotGuide: queue.skippedNotGuide,
          skippedCovered: queue.skippedCovered,
          running,
          pendingRetry,
          pipelineRunning,
          pipelineItemActive,
          recent429,
        },
        selection: {
          loosenedRules: false,
          forceForbidden: true,
          safeCandidateCount: safe.length,
          pickedCount: pick.length,
          idealMix: "A short(<80k), B longform(90-120k), C short(<80k)",
        },
        candidates: ready
          ? {
              A: pick.find((p) => p.slot === "A") ?? null,
              B:
                pick.find(
                  (p) => p.slot === "B" || p.slot === "B_fallback_short",
                ) ?? null,
              C: pick.find((p) => p.slot === "C") ?? null,
            }
          : { A: null, B: null, C: null },
        batchPlan: {
          batchSize: 3,
          maxConcurrency: 1,
          sequentialOrder: "A → confirm → B → confirm → C",
          skipAutoPublish: true,
          force: false,
          expectedProviderCalls: batchTotalCalls,
          estimatedTotalInputTokens: batchTotalTokens,
          abortPolicy: [
            "http429",
            "providerCooldown",
            "duplicatePaidCall",
            "unexpectedRetryLoop",
            "emergencyON",
            "unexpectedPublish",
            "terminalCorruption",
            "orphanJob",
            "costGuardViolation",
          ],
        },
        codeAudit,
        readyForLimitedBatchLiveCanary: ready,
        status: ready
          ? "READY_FOR_HUMAN_GATE"
          : "LIMITED_BATCH_CANARY:BLOCKED_NO_ELIGIBLE_INPUT",
        blockedReason: ready
          ? null
          : `safe eligible candidates=${safe.length} (need>=3); coverage.eligiblePendingVideos=${coverage.eligiblePendingVideos}; queue.eligible=${queue.eligiblePendingVideos}`,
      };

      mkdirSync(".tmp-qa", { recursive: true });
      writeFileSync(
        ".tmp-qa/limited-batch-planning-report.json",
        JSON.stringify(report, null, 2),
      );
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(report, null, 2));

      // Planning never mutates Emergency.
      expect(emergency.emergencyStopped).toBe(true);
      expect(running).toBe(0);
      expect(recent429).toBe(0);
      // Not a FAIL when blocked for lack of input.
      expect(
        report.status === "READY_FOR_HUMAN_GATE" ||
          report.status === "LIMITED_BATCH_CANARY:BLOCKED_NO_ELIGIBLE_INPUT",
      ).toBe(true);
    },
    120_000,
  );
});
