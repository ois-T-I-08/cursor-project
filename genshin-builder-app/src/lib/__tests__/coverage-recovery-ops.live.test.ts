/**
 * Live: Coverage Recovery Operational Verification.
 * Enable: COVERAGE_RECOVERY_OPS_LIVE=1
 * Never calls Gemini/DeepSeek/analyze/publish. Does not change Emergency.
 */
import { describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { readGlobalAiEmergencyControl } from "@/lib/ai/global-ai-emergency";
import {
  getCoverageMetrics,
  recoverPostProcessFailures,
  listRecoverablePostProcessFailureVideoIds,
} from "@/lib/build-guides/visual-coverage";
import { writeFileSync } from "node:fs";

const enabled = process.env.COVERAGE_RECOVERY_OPS_LIVE === "1";

async function usageCounts() {
  const [all, gemini, deepseek, publishedRecs] = await Promise.all([
    prisma.guideVisualUsageLog.count(),
    prisma.guideVisualUsageLog.count({
      where: {
        OR: [
          { providerId: { contains: "gemini" } },
          { modelIdentifier: { contains: "gemini" } },
        ],
      },
    }),
    prisma.guideVisualUsageLog.count({
      where: {
        OR: [
          { providerId: { contains: "deepseek" } },
          { modelIdentifier: { contains: "deepseek" } },
        ],
      },
    }),
    prisma.characterBuildRecommendation.count({
      where: { status: "published" },
    }),
  ]);
  return { all, gemini, deepseek, publishedRecs };
}

function parsePostProcess(job: {
  status: string;
  errorCode: string;
  rangesPayload: string;
}) {
  let pp: { status?: string; code?: string } | null = null;
  try {
    const ranges = JSON.parse(job.rangesPayload || "{}") as {
      postProcess?: { status?: string; code?: string };
    };
    pp = ranges.postProcess ?? null;
  } catch {
    pp = null;
  }
  return {
    jobStatus: job.status,
    errorCode: job.errorCode || "",
    postProcessStatus: pp?.status ?? null,
    postProcessCode: pp?.code ?? null,
  };
}

async function videoState(videoId: string) {
  const job = await prisma.guideVisualAnalysisJob.findFirst({
    where: { videoId, status: "succeeded" },
    orderBy: { completedAt: "desc" },
  });
  const contrib = await prisma.recommendationVisualContribution.count({
    where: {
      videoId,
      recommendation: { status: { not: "rejected" } },
    },
  });
  return {
    job: job ? parsePostProcess(job) : null,
    recommendationCount: contrib,
    coveredByRec: contrib > 0,
  };
}

describe.skipIf(!enabled)("Coverage Recovery Operational Verification", () => {
  it(
    "snapshot + optional recoverPostProcessFailures(limit=3)",
    async () => {
      const emergencyBefore = await readGlobalAiEmergencyControl();
      // Do not mutate Emergency. If OFF, still snapshot; skip recovery; gate FAIL.

      const usageBefore = await usageCounts();
      const coverageBefore = await getCoverageMetrics({ eligibleLimit: 3 });

      const allRecs = await prisma.characterBuildRecommendation.findMany({
        select: { characterId: true, status: true },
      });
      const covered = new Set<string>();
      const published = new Set<string>();
      const pending = new Set<string>();
      const rejectedOnlyChars = new Set<string>();
      const byChar = new Map<string, Set<string>>();
      for (const r of allRecs) {
        const s = byChar.get(r.characterId) ?? new Set();
        s.add(r.status);
        byChar.set(r.characterId, s);
      }
      for (const [id, statuses] of byChar) {
        const nonRejected = [...statuses].filter((s) => s !== "rejected");
        if (nonRejected.length === 0) {
          rejectedOnlyChars.add(id);
          continue;
        }
        covered.add(id);
        if (statuses.has("published")) published.add(id);
        if (statuses.has("pending_review")) pending.add(id);
      }

      const integrity = {
        sumOk:
          coverageBefore.totalCharacters ===
          coverageBefore.coveredCharacters + coverageBefore.uncoveredCharacters,
        publishedSubset: [...published].every((id) => covered.has(id)),
        pendingSubset: [...pending].every((id) => covered.has(id)),
        coveredMatches:
          covered.size === coverageBefore.coveredCharacters &&
          [...published].every((id) => covered.has(id)) &&
          [...pending].every((id) => covered.has(id)),
        rejectedOnlyNotCovered: [...rejectedOnlyChars].every(
          (id) => !covered.has(id),
        ),
        evidenceOnlyNotInCovered: true as boolean,
      };

      const claims = await prisma.guideVisualExtractedClaim.findMany({
        distinct: ["characterId"],
        select: { characterId: true },
      });
      const evidenceOnlyIds = claims
        .map((c) => c.characterId)
        .filter(
          (id): id is string =>
            typeof id === "string" && id.length > 0 && !covered.has(id),
        );
      integrity.evidenceOnlyNotInCovered = evidenceOnlyIds.every(
        (id) => !covered.has(id),
      );
      expect(evidenceOnlyIds.length).toBe(
        coverageBefore.evidenceOnlyCharacters,
      );

      expect(integrity.sumOk).toBe(true);
      expect(integrity.rejectedOnlyNotCovered).toBe(true);
      expect(integrity.evidenceOnlyNotInCovered).toBe(true);

      // Title fail classification (no AI)
      const pendingVideos = await prisma.guideVideo.findMany({
        where: {
          title: { contains: "【原神】" },
          analysisStatus: { not: "analyzed" },
          privacyStatus: "public",
          channel: {
            enabled: true,
            permissionStatus: "approved_for_processing",
          },
        },
        take: 500,
        select: { title: true },
      });
      const hints = await prisma.character.findMany({
        select: { id: true, name: true },
      });
      const nameSet = new Set(
        hints.map((h) => h.name.trim().toLowerCase()).filter(Boolean),
      );
      const titleClass: Record<string, number> = {};
      const aliasCandidates: string[] = [];
      for (const v of pendingVideos) {
        const guide =
          /おすすめ武器|聖遺物|目標ステータス|育成|ビルド|ステータスガイド|完全解説|最新解説|最新ガイド|正しい育成/.test(
            v.title,
          );
        if (!guide) continue;
        const quoted = [...v.title.matchAll(/「([^」]{1,40})」/g)].map(
          (m) => m[1]!.trim(),
        );
        const resolved = quoted.some((q) => nameSet.has(q.toLowerCase()));
        const loose = hints.some(
          (h) =>
            h.name.trim().length >= 2 &&
            v.title.toLowerCase().includes(h.name.trim().toLowerCase()),
        );
        if (resolved || loose) continue;
        let reason = "parser ambiguity";
        if (
          /新聖遺物|聖遺物セット|教官聖遺物|乗り換え|おすすめキャラ/.test(v.title) &&
          quoted.length === 0
        ) {
          reason = "set/build解説";
        } else if (quoted[0]) {
          reason = "master外キャラクター名";
          aliasCandidates.push(quoted[0]);
        }
        titleClass[reason] = (titleClass[reason] ?? 0) + 1;
      }

      const recoverableIds = await listRecoverablePostProcessFailureVideoIds(20);
      expect(recoverableIds.length).toBe(
        coverageBefore.recoverablePostProcessFailures,
      );

      let recovery: Awaited<ReturnType<typeof recoverPostProcessFailures>> | null =
        null;
      const perVideo: Array<{
        videoId: string;
        before: Awaited<ReturnType<typeof videoState>>;
        after: Awaited<ReturnType<typeof videoState>> | null;
        ok: boolean | null;
        error: string | null;
        terminalPreserved: boolean | null;
      }> = [];

      const mayRecover =
        emergencyBefore.emergencyStopped === true && recoverableIds.length > 0;
      if (mayRecover) {
        for (const videoId of recoverableIds.slice(0, 3)) {
          perVideo.push({
            videoId,
            before: await videoState(videoId),
            after: null,
            ok: null,
            error: null,
            terminalPreserved: null,
          });
        }
        recovery = await recoverPostProcessFailures({ limit: 3 });
        expect(recovery.aiCalls).toBe(0);
        expect(recovery.attempted).toBeLessThanOrEqual(3);
        for (const row of perVideo) {
          const r = recovery.results.find((x) => x.videoId === row.videoId);
          row.after = await videoState(row.videoId);
          row.ok = r?.ok ?? null;
          row.error = r?.error ?? null;
          row.terminalPreserved = row.after.job?.jobStatus === "succeeded";
          expect(row.terminalPreserved).toBe(true);
        }
      }

      const usageAfter = await usageCounts();
      const emergencyAfter = await readGlobalAiEmergencyControl();
      const coverageAfter = recovery?.coverage ?? coverageBefore;

      const deltas = {
        geminiUsage: usageAfter.gemini - usageBefore.gemini,
        deepseekUsage: usageAfter.deepseek - usageBefore.deepseek,
        allUsage: usageAfter.all - usageBefore.all,
        publishedRecs: usageAfter.publishedRecs - usageBefore.publishedRecs,
      };
      expect(deltas.geminiUsage).toBe(0);
      expect(deltas.deepseekUsage).toBe(0);
      expect(deltas.allUsage).toBe(0);
      expect(deltas.publishedRecs).toBe(0);
      // Emergency must not be changed by this ops run.
      expect(emergencyAfter.emergencyStopped).toBe(
        emergencyBefore.emergencyStopped,
      );

      const report = {
        emergencyBefore: {
          emergencyStopped: emergencyBefore.emergencyStopped,
          version: emergencyBefore.version,
        },
        snapshot: {
          totalCharacters: coverageBefore.totalCharacters,
          coveredCharacters: coverageBefore.coveredCharacters,
          uncoveredCharacters: coverageBefore.uncoveredCharacters,
          publishedCharacters: coverageBefore.publishedCharacters,
          pendingReviewCharacters: coverageBefore.pendingReviewCharacters,
          evidenceOnlyCharacters: coverageBefore.evidenceOnlyCharacters,
          recoverablePostProcessFailures:
            coverageBefore.recoverablePostProcessFailures,
          eligiblePendingVideos: coverageBefore.eligiblePendingVideos,
          remainingEligibleVideos: coverageBefore.remainingEligibleVideos,
          titleResolutionFailedVideos:
            coverageBefore.titleResolutionFailedVideos,
        },
        integrity,
        recoverableCount: recoverableIds.length,
        recoveryExecuted: recovery?.attempted ?? 0,
        recoverySucceeded: recovery?.succeeded ?? 0,
        recoveryFailed: recovery?.failed ?? 0,
        recoveryPerVideo: perVideo,
        aiUsageDelta: deltas,
        publishDelta: deltas.publishedRecs,
        coverageAfter: {
          totalCharacters: coverageAfter.totalCharacters,
          coveredCharacters: coverageAfter.coveredCharacters,
          uncoveredCharacters: coverageAfter.uncoveredCharacters,
          publishedCharacters: coverageAfter.publishedCharacters,
          pendingReviewCharacters: coverageAfter.pendingReviewCharacters,
          evidenceOnlyCharacters: coverageAfter.evidenceOnlyCharacters,
          recoverablePostProcessFailures:
            coverageAfter.recoverablePostProcessFailures,
          eligiblePendingVideos: coverageAfter.eligiblePendingVideos,
          remainingEligibleVideos: coverageAfter.remainingEligibleVideos,
          titleResolutionFailedVideos:
            coverageAfter.titleResolutionFailedVideos,
        },
        coverageDelta: {
          covered:
            coverageAfter.coveredCharacters - coverageBefore.coveredCharacters,
          uncovered:
            coverageAfter.uncoveredCharacters -
            coverageBefore.uncoveredCharacters,
          recoverable:
            coverageAfter.recoverablePostProcessFailures -
            coverageBefore.recoverablePostProcessFailures,
        },
        titleResolutionClassification: titleClass,
        manualAliasCandidates: [...new Set(aliasCandidates)].slice(0, 15),
        deprecatedField:
          "remainingUncoveredEstimate alias only; ops uses remainingEligibleVideos",
        emergencyFinal: {
          emergencyStopped: emergencyAfter.emergencyStopped,
          version: emergencyAfter.version,
        },
        skippedRecovery:
          recoverableIds.length === 0
            ? "recoverablePostProcessFailures=0"
            : !emergencyBefore.emergencyStopped
              ? "skipped: Emergency OFF (not mutated); recovery not run"
              : null,
        gate: {
          snapshotIntegrity: integrity.sumOk && integrity.rejectedOnlyNotCovered && integrity.evidenceOnlyNotInCovered,
          emergencyOn: emergencyAfter.emergencyStopped === true,
          emergencyUnchanged:
            emergencyAfter.emergencyStopped ===
            emergencyBefore.emergencyStopped,
          recoveryAiZero:
            deltas.geminiUsage === 0 &&
            deltas.deepseekUsage === 0 &&
            deltas.allUsage === 0,
          publishZero: deltas.publishedRecs === 0,
          pass:
            integrity.sumOk &&
            integrity.rejectedOnlyNotCovered &&
            integrity.evidenceOnlyNotInCovered &&
            emergencyAfter.emergencyStopped === true &&
            deltas.geminiUsage === 0 &&
            deltas.publishedRecs === 0,
        },
      };

      writeFileSync(
        "scripts/_tmp-coverage-recovery-ops-report.json",
        JSON.stringify(report, null, 2),
        "utf8",
      );
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(report, null, 2));

      // Operational gate: Emergency must be ON for PASS (do not flip it here).
      if (!report.gate.pass) {
        // Keep report on disk; fail with actionable message (no Emergency mutation).
        expect.fail(
          `Coverage Recovery Ops gate FAIL: emergencyOn=${report.gate.emergencyOn} integrity=${report.gate.snapshotIntegrity} aiZero=${report.gate.recoveryAiZero} publishZero=${report.gate.publishZero}`,
        );
      }
    },
    180_000,
  );
});
