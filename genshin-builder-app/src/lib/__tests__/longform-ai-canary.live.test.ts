/**
 * Long-form AI Canary (1 video). Opt-in.
 *
 * Plan only (Emergency stays ON):
 *   $env:LONGFORM_CANARY_LIVE="1"; $env:LONGFORM_CANARY_CMD="plan"
 *   node --env-file=.env ./node_modules/vitest/vitest.mjs run src/lib/__tests__/longform-ai-canary.live.test.ts
 *
 * Wait until admin turns Emergency OFF (no DB bypass):
 *   $env:LONGFORM_CANARY_CMD="wait-off"
 *
 * Run canary (requires Emergency OFF). Publish forced off.
 *   $env:LONGFORM_CANARY_CMD="run"
 *   $env:GEMINI_VIDEO_MAX_RANGE_SECONDS="360"
 *
 * Re-engage Emergency via Safety Switch helper (same as admin path):
 *   $env:LONGFORM_CANARY_CMD="emergency-on"
 */
import { PrismaClient } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { setYoutubeAutomationEmergencyStop } from "@/lib/build-guides/automation/admin-overview";
import {
  analyzeVideoVisuals,
  GuideVisualAnalysisError,
} from "@/lib/build-guides/visual-analysis-service";
import {
  estimateVisualPromptTokens,
  VISUAL_PROMPT_TOKEN_HARD_MAX,
} from "@/lib/build-guides/visual-analysis-safety";
import {
  extractLongformChunkUsage,
  LONGFORM_OVERLAP_SECONDS,
  planLongformChunks,
} from "@/lib/build-guides/visual-longform";

const enabled = process.env.LONGFORM_CANARY_LIVE === "1";
const cmd = process.env.LONGFORM_CANARY_CMD ?? "plan";
/** Picked by dry-plan: 1011s → 3 chunks @ maxRange 360. */
const VIDEO_ID = process.env.LONGFORM_CANARY_VIDEO_ID ?? "gR-wnOJNMMk";
const PLAN_MAX_RANGE = Number(process.env.GEMINI_VIDEO_MAX_RANGE_SECONDS ?? "360");

const prisma = new PrismaClient();

async function readControl() {
  return prisma.guideAutomationControl.findUnique({
    where: { id: "youtube-guide" },
    select: {
      emergencyStopped: true,
      version: true,
      reason: true,
      updatedAt: true,
    },
  });
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

describe.skipIf(!enabled)("Long-form AI Canary (live)", () => {
  it(
    `CMD=${cmd} video=${VIDEO_ID}`,
    async () => {
      const video = await prisma.guideVideo.findUnique({
        where: { videoId: VIDEO_ID },
        select: {
          videoId: true,
          title: true,
          durationSeconds: true,
          analysisStatus: true,
        },
      });
      expect(video).toBeTruthy();
      const duration = video!.durationSeconds ?? 0;
      const originalEstimatedTokens = estimateVisualPromptTokens({
        durationSeconds: duration,
        fps: 1,
        analysisMode: "full_discovery",
        targetCharacterCount: 1,
      });
      expect(originalEstimatedTokens).toBeGreaterThan(VISUAL_PROMPT_TOKEN_HARD_MAX);

      const plan = planLongformChunks({
        videoId: VIDEO_ID,
        durationSeconds: duration,
        fps: 1,
        targetCharacterCount: 1,
        maxRangeSeconds: PLAN_MAX_RANGE,
      });

      const planReport = {
        videoId: VIDEO_ID,
        title: video!.title.slice(0, 100),
        durationSeconds: duration,
        analysisStatus: video!.analysisStatus,
        originalEstimatedTokens,
        hardMax: VISUAL_PROMPT_TOKEN_HARD_MAX,
        planningMaxRangeSeconds: PLAN_MAX_RANGE,
        chunkCount: plan.chunks.length,
        overlap: plan.overlapSeconds ?? LONGFORM_OVERLAP_SECONDS,
        chunks: plan.chunks.map((c) => ({
          i: c.chunkIndex,
          range: [c.startSeconds, c.endSeconds],
          estimatedTokens: c.estimatedTokens,
        })),
        expectedProviderCalls: plan.estimatedAiCalls,
        expectedMergeCalls: 0,
        estimatedTotalInputTokens: plan.estimatedInputTokens,
        costGuardHeadroomChunks: 40 - plan.chunks.length,
      };

      if (cmd === "plan") {
        const control = await readControl();
        // eslint-disable-next-line no-console
        console.log(
          JSON.stringify({ phase: "plan", control, plan: planReport }, null, 2),
        );
        expect(plan.chunks.length).toBeGreaterThanOrEqual(2);
        expect(plan.chunks.length).toBeLessThanOrEqual(5);
        expect(control?.emergencyStopped).toBe(true);
        return;
      }

      if (cmd === "wait-off") {
        const deadline = Date.now() + 20 * 60_000;
        // eslint-disable-next-line no-console
        console.log(
          JSON.stringify({
            phase: "wait-off-start",
            message:
              "Waiting for admin UI Emergency OFF (DB bypass forbidden)",
          }),
        );
        while (Date.now() < deadline) {
          const control = await readControl();
          if (control && !control.emergencyStopped) {
            // eslint-disable-next-line no-console
            console.log(
              JSON.stringify({
                phase: "wait-off-ready",
                control: {
                  emergencyStopped: control.emergencyStopped,
                  version: control.version,
                  reason: control.reason,
                  updatedAt: control.updatedAt,
                },
              }),
            );
            expect(control.emergencyStopped).toBe(false);
            return;
          }
          await sleep(5_000);
        }
        throw new Error("TIMEOUT waiting for Emergency OFF via admin");
      }

      if (cmd === "emergency-on") {
        const control = await setYoutubeAutomationEmergencyStop({
          emergencyStopped: true,
          reason: "longform canary complete — re-engage Global AI Emergency",
        });
        // eslint-disable-next-line no-console
        console.log(
          JSON.stringify({
            phase: "emergency-on",
            control: {
              emergencyStopped: control.emergencyStopped,
              version: control.version,
              reason: control.reason,
              updatedAt: control.updatedAt,
            },
          }),
        );
        expect(control.emergencyStopped).toBe(true);
        return;
      }

      if (cmd !== "run") {
        throw new Error(`unknown LONGFORM_CANARY_CMD=${cmd}`);
      }

      // --- RUN ---
      if (PLAN_MAX_RANGE < 300) {
        throw new Error(
          "ABORT: set GEMINI_VIDEO_MAX_RANGE_SECONDS=360 for this canary plan",
        );
      }
      if (plan.chunks.length > 5) {
        throw new Error("ABORT: chunk count > 5 — refuse canary");
      }

      const controlBefore = await readControl();
      if (controlBefore?.emergencyStopped) {
        throw new Error(
          "ABORT: Emergency still ON — human must disable via admin UI first",
        );
      }

      const usageBefore = await prisma.guideVisualUsageLog.count();
      const jobsBefore = await prisma.guideVisualAnalysisJob.count({
        where: { videoId: VIDEO_ID },
      });
      const publishedBefore =
        await prisma.recommendationVisualContribution.count({
          where: { videoId: VIDEO_ID, usedInPublishedResult: true },
        });

      // eslint-disable-next-line no-console
      console.log(
        JSON.stringify(
          {
            phase: "run-start",
            control: controlBefore,
            plan: planReport,
            usageBefore,
            jobsBefore,
            publishedBefore,
          },
          null,
          2,
        ),
      );

      let outcome: Awaited<ReturnType<typeof analyzeVideoVisuals>> | null =
        null;
      let errorCode: string | null = null;
      try {
        outcome = await analyzeVideoVisuals({
          videoId: VIDEO_ID,
          force: true,
          allowLongform: true,
          skipAutoPublish: true,
        });
      } catch (e) {
        errorCode =
          e instanceof GuideVisualAnalysisError
            ? e.code
            : e instanceof Error
              ? e.message
              : "unknown";
      }

      const usageAfter = await prisma.guideVisualUsageLog.count();
      const jobsAfter = await prisma.guideVisualAnalysisJob.count({
        where: { videoId: VIDEO_ID },
      });
      const publishedAfter =
        await prisma.recommendationVisualContribution.count({
          where: { videoId: VIDEO_ID, usedInPublishedResult: true },
        });
      const job = await prisma.guideVisualAnalysisJob.findFirst({
        where: { videoId: VIDEO_ID },
        orderBy: { createdAt: "desc" },
        select: {
          id: true,
          status: true,
          errorCode: true,
          attempts: true,
          tokenUsage: true,
          rangesPayload: true,
        },
      });
      const running = await prisma.guideVisualAnalysisJob.count({
        where: { videoId: VIDEO_ID, status: "running" },
      });
      const controlAfterRun = await readControl();

      let postProcess: unknown = null;
      let longformMeta: unknown = null;
      let ranges: Record<string, unknown> = {};
      try {
        ranges = JSON.parse(job?.rangesPayload || "{}") as Record<
          string,
          unknown
        >;
        postProcess = ranges.postProcess ?? null;
        longformMeta = ranges.longform ?? ranges.plan ?? null;
      } catch {
        /* ignore */
      }

      const chunkUsage = extractLongformChunkUsage(ranges);
      const chunkUsageSafe = chunkUsage.map((c) => ({
        chunkIndex: c.chunkIndex,
        rangeStart: c.rangeStart,
        rangeEnd: c.rangeEnd,
        estimatedTokens: c.estimatedTokens,
        actualPromptTokens: c.actualPromptTokens,
        actualCandidateTokens: c.actualCandidateTokens,
        actualTotalTokens: c.actualTotalTokens,
        attempts: c.attempts,
        retryCount: c.retryCount,
        cacheHit: c.cacheHit,
        provider: c.provider,
        requestHashPresent: Boolean(c.requestHash),
        requestHashLen: c.requestHash.length,
      }));
      const chunkSum = chunkUsage.reduce(
        (acc, c) => ({
          prompt: acc.prompt + (c.actualPromptTokens ?? 0),
          candidates: acc.candidates + (c.actualCandidateTokens ?? 0),
          total: acc.total + (c.actualTotalTokens ?? 0),
          nullActuals: acc.nullActuals + (c.actualTotalTokens == null ? 1 : 0),
          cacheHits: acc.cacheHits + (c.cacheHit ? 1 : 0),
          paid: acc.paid + (c.cacheHit ? 0 : 1),
          retries: acc.retries + c.retryCount,
        }),
        {
          prompt: 0,
          candidates: 0,
          total: 0,
          nullActuals: 0,
          cacheHits: 0,
          paid: 0,
          retries: 0,
        },
      );
      let jobUsage: Record<string, number> = {};
      try {
        jobUsage = JSON.parse(job?.tokenUsage || "{}") as Record<string, number>;
      } catch {
        jobUsage = {};
      }

      const report = {
        phase: "run-result",
        errorCode,
        outcome: outcome
          ? {
              jobId: outcome.jobId,
              status: outcome.status,
              evidenceCount: outcome.evidenceCount,
              recommendationIds: outcome.recommendationIds,
              analysisMode: outcome.analysisMode,
              fps: outcome.fps,
              autoPublish: outcome.autoPublish ?? null,
            }
          : null,
        job: job
          ? {
              id: job.id,
              status: job.status,
              errorCode: job.errorCode,
              attempts: job.attempts,
              tokenUsage: jobUsage,
            }
          : null,
        postProcess,
        longformMeta,
        chunkUsage: chunkUsageSafe,
        chunkUsageSum: chunkSum,
        aggregateDiff: {
          prompt:
            (jobUsage.promptTokenCount ?? 0) - chunkSum.prompt,
          candidates:
            (jobUsage.candidatesTokenCount ?? 0) - chunkSum.candidates,
          total: (jobUsage.totalTokenCount ?? 0) - chunkSum.total,
        },
        aiUsageDelta: usageAfter - usageBefore,
        aiJobDelta: jobsAfter - jobsBefore,
        publishDelta: publishedAfter - publishedBefore,
        running,
        controlAfterRun,
      };
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(report, null, 2));

      // Always try to leave a clear signal for the emergency-on step.
      expect(publishedAfter - publishedBefore).toBe(0);
      expect(outcome?.autoPublish ?? null).toBeNull();
      if (errorCode) {
        throw new Error(`canary_failed:${errorCode}`);
      }
      expect(outcome?.status).toBe("validated");
      expect(job?.status).toBe("succeeded");
      // Observability: new runs must persist per-chunk usage (no invented actuals).
      expect(chunkUsage.length).toBe(plan.chunks.length);
      const paidChunks = chunkUsage.filter((c) => !c.cacheHit);
      for (const c of paidChunks) {
        expect(c.actualPromptTokens).not.toBeNull();
        expect(c.actualCandidateTokens).not.toBeNull();
        expect(c.actualTotalTokens).not.toBeNull();
        expect(c.requestHash.length).toBeGreaterThan(0);
      }
    },
    45 * 60_000,
  );
});
