/**
 * Live: retryVisualPostProcess for QPjYaNXMNd0 with Global AI Emergency ON.
 *
 *   node --env-file=.env ./node_modules/vitest/vitest.mjs run src/lib/__tests__/retry-qpj-postprocess.live.test.ts
 *
 *   $env:RETRY_POSTPROCESS_LIVE="1"
 *
 * Does NOT mutate Emergency. Does NOT call Gemini/DeepSeek (deterministic path only).
 * Does NOT publish / autoPublish.
 */
import { PrismaClient } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { retryVisualPostProcessOnly } from "@/lib/build-guides/visual-postprocess";

const enabled = process.env.RETRY_POSTPROCESS_LIVE === "1";
const VIDEO_ID = "QPjYaNXMNd0";
const prisma = new PrismaClient();

function parsePostProcess(rangesPayload: string): {
  status: string | null;
  code: string | null;
  attempts: number | null;
} {
  try {
    const ranges = JSON.parse(rangesPayload || "{}") as {
      postProcess?: { status?: string; code?: string; attempts?: number };
    };
    const pp = ranges.postProcess;
    return {
      status: pp?.status ?? null,
      code: typeof pp?.code === "string" ? pp.code : null,
      attempts: typeof pp?.attempts === "number" ? pp.attempts : null,
    };
  } catch {
    return { status: null, code: null, attempts: null };
  }
}

async function snapshot() {
  const control = await prisma.guideAutomationControl.findUnique({
    where: { id: "youtube-guide" },
    select: {
      emergencyStopped: true,
      version: true,
      reason: true,
      updatedAt: true,
    },
  });
  const job = await prisma.guideVisualAnalysisJob.findFirst({
    where: { videoId: VIDEO_ID, status: "succeeded" },
    orderBy: { completedAt: "desc" },
    select: {
      id: true,
      status: true,
      errorCode: true,
      rangesPayload: true,
      attempts: true,
      completedAt: true,
    },
  });
  const usageCount = await prisma.guideVisualUsageLog.count();
  const usageForVideo = await prisma.guideVisualUsageLog.count({
    where: { videoId: VIDEO_ID },
  });
  const jobsForVideo = await prisma.guideVisualAnalysisJob.count({
    where: { videoId: VIDEO_ID },
  });
  const publishedViaVideo = await prisma.recommendationVisualContribution.count({
    where: { videoId: VIDEO_ID, usedInPublishedResult: true },
  });
  const pendingRecs = await prisma.characterBuildRecommendation.count({
    where: {
      status: "pending_review",
      contributions: { some: { videoId: VIDEO_ID } },
    },
  });
  const validatedEvidence = await prisma.guideVisualEvidence.count({
    where: {
      videoId: VIDEO_ID,
      validationStatus: "validated",
      approvalStatus: { not: "rejected" },
    },
  });
  const pp = parsePostProcess(job?.rangesPayload ?? "");
  return {
    control,
    job: job
      ? {
          id: job.id,
          status: job.status,
          errorCode: job.errorCode,
          attempts: job.attempts,
          postProcessStatus: pp.status,
          postProcessCode: pp.code,
          postProcessAttempts: pp.attempts,
        }
      : null,
    usageCount,
    usageForVideo,
    jobsForVideo,
    publishedViaVideo,
    pendingRecs,
    validatedEvidence,
  };
}

describe.skipIf(!enabled)("retryVisualPostProcess QPjYaNXMNd0 (live)", () => {
  it(
    "post-process only with Emergency ON; AI delta 0",
    async () => {
      const before = await snapshot();

      // eslint-disable-next-line no-console
      console.log(JSON.stringify({ phase: "before", ...before }, null, 2));

      if (!before.control?.emergencyStopped) {
        throw new Error(
          "ABORT: Global AI Emergency is OFF — refusing to run (keep ON)",
        );
      }
      if (!before.job || before.job.status !== "succeeded") {
        throw new Error("ABORT: no succeeded job for video");
      }
      if (before.validatedEvidence < 1) {
        throw new Error("ABORT: no validated evidence to reuse");
      }

      // Static safety: retry path must not invoke analyzeVideoVisuals / providers.
      // (Import graph checked at authoring time; runtime only calls retryVisualPostProcessOnly.)

      let outcome: {
        recommendationIds: string[];
        attempts: number;
        jobId: string | null;
      };
      let error: string | null = null;
      try {
        outcome = await retryVisualPostProcessOnly(VIDEO_ID);
      } catch (e) {
        error = e instanceof Error ? e.message : String(e);
        const afterFail = await snapshot();
        // eslint-disable-next-line no-console
        console.log(
          JSON.stringify(
            { phase: "after-error", error, after: afterFail },
            null,
            2,
          ),
        );
        throw e;
      }

      const after = await snapshot();
      const usageDelta = after.usageCount - before.usageCount;
      const jobDelta = after.jobsForVideo - before.jobsForVideo;
      const publishDelta = after.publishedViaVideo - before.publishedViaVideo;

      const report = {
        phase: "after",
        emergencyStillOn: after.control?.emergencyStopped === true,
        emergencyVersion: after.control?.version,
        jobStatus: after.job?.status ?? null,
        postProcessStatus: after.job?.postProcessStatus ?? null,
        postProcessCode: after.job?.postProcessCode ?? null,
        postProcessAttempts: after.job?.postProcessAttempts ?? null,
        jobErrorCode: after.job?.errorCode ?? null,
        attempts: outcome.attempts,
        recommendationIds: outcome.recommendationIds,
        recommendationCount: outcome.recommendationIds.length,
        aiUsageDelta: usageDelta,
        aiUsageForVideoDelta: after.usageForVideo - before.usageForVideo,
        aiJobDelta: jobDelta,
        publishDelta,
        pendingRecsBefore: before.pendingRecs,
        pendingRecsAfter: after.pendingRecs,
        error,
      };
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(report, null, 2));

      expect(after.control?.emergencyStopped).toBe(true);
      expect(after.job?.status).toBe("succeeded");
      expect(after.job?.postProcessStatus).toBe("succeeded");
      expect(usageDelta).toBe(0);
      expect(jobDelta).toBe(0);
      expect(publishDelta).toBe(0);
      expect(after.job?.errorCode.startsWith("postProcess:") ?? false).toBe(
        false,
      );
      expect(outcome.recommendationIds.length).toBeGreaterThan(0);
    },
    120_000,
  );
});
