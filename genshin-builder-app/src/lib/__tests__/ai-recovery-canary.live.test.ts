/**
 * Live AI Recovery Canary (opt-in).
 *
 *   node --env-file=.env ./node_modules/vitest/vitest.mjs run src/lib/__tests__/ai-recovery-canary.live.test.ts
 *
 * Commands via env:
 *   CANARY_CMD=prove-on|run|cache-check
 *   CANARY_VIDEO_ID=<id>
 *
 * Does not mutate Global AI Emergency.
 */
import { PrismaClient } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { setYoutubeAutomationEmergencyStop } from "@/lib/build-guides/automation/admin-overview";
import {
  analyzeVideoVisuals,
  GuideVisualAnalysisError,
} from "@/lib/build-guides/visual-analysis-service";
import { estimateVisualPromptTokens } from "@/lib/build-guides/visual-analysis-safety";

const enabled = process.env.CANARY_LIVE === "1";
const cmd = process.env.CANARY_CMD ?? "prove-on";
const videoId = process.env.CANARY_VIDEO_ID ?? "brtPf45QxRk";

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

describe.skipIf(!enabled)("AI Recovery Canary (live)", () => {
  it(
    `CANARY_CMD=${cmd} video=${videoId}`,
    async () => {
      try {
        if (cmd === "emergency-on") {
          // Same Safety Switch path as admin UI (not a DB bypass).
          const control = await setYoutubeAutomationEmergencyStop({
            emergencyStopped: true,
            reason: "canary retest stop after AI Recovery Canary",
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

        if (cmd === "prove-on") {
          const control = await readControl();
          expect(control?.emergencyStopped).toBe(true);
          const usageBefore = await prisma.guideVisualUsageLog.count();
          const jobsBefore = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          let code = "none";
          try {
            await analyzeVideoVisuals({ videoId, force: true });
            code = "unexpectedSuccess";
          } catch (e) {
            code =
              e instanceof GuideVisualAnalysisError
                ? e.code
                : e instanceof Error
                  ? e.message
                  : "unknown";
          }
          const usageAfter = await prisma.guideVisualUsageLog.count();
          const jobsAfter = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          // eslint-disable-next-line no-console
          console.log(
            JSON.stringify({
              phase: "prove-on",
              code,
              usageLogDelta: usageAfter - usageBefore,
              jobDelta: jobsAfter - jobsBefore,
              control,
            }),
          );
          expect(["emergencyStopped", "EMERGENCY_STOPPED"]).toContain(code);
          expect(usageAfter - usageBefore).toBe(0);
          expect(jobsAfter - jobsBefore).toBe(0);
          return;
        }

        if (cmd === "run") {
          const control = await readControl();
          expect(control?.emergencyStopped).toBe(false);
          const video = await prisma.guideVideo.findUniqueOrThrow({
            where: { videoId },
          });
          const estimatedTokens = estimateVisualPromptTokens({
            durationSeconds: video.durationSeconds,
            fps: 1,
            analysisMode: "full_discovery",
            targetCharacterCount: 1,
          });
          expect(estimatedTokens).toBeLessThanOrEqual(50_000);

          const jobsBefore = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          const startedAt = new Date();
          const outcome = await analyzeVideoVisuals({ videoId, force: true });
          const latest = await prisma.guideVisualAnalysisJob.findFirst({
            where: { videoId, createdAt: { gte: startedAt } },
            orderBy: { createdAt: "desc" },
          });
          const jobsAfter = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          let usage: Record<string, number> | null = null;
          try {
            usage = latest?.tokenUsage
              ? (JSON.parse(latest.tokenUsage) as Record<string, number>)
              : null;
          } catch {
            usage = null;
          }
          // eslint-disable-next-line no-console
          console.log(
            JSON.stringify({
              phase: "run",
              videoId,
              estimatedTokens,
              control,
              outcomeStatus: outcome.status,
              jobId: outcome.jobId,
              latestStatus: latest?.status ?? null,
              attempts: latest?.attempts ?? null,
              errorCode: latest?.errorCode ?? null,
              promptTokenCount: usage?.promptTokenCount ?? null,
              candidatesTokenCount: usage?.candidatesTokenCount ?? null,
              totalTokenCount: usage?.totalTokenCount ?? null,
              newJobs: jobsAfter - jobsBefore,
            }),
          );
          expect(latest?.status).toBe("succeeded");
          expect(latest?.attempts).toBeLessThanOrEqual(1);
          expect(latest?.errorCode ?? "").not.toMatch(/http429/);
          expect(jobsAfter - jobsBefore).toBe(1);
          // Terminal succeeded must not be overwritten to failed.
          expect(latest?.status).not.toBe("failed");
          return;
        }

        if (cmd === "cache-check") {
          const control = await readControl();
          expect(control?.emergencyStopped).toBe(false);
          const usageBefore = await prisma.guideVisualUsageLog.count({
            where: { success: true },
          });
          const jobsBefore = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          const outcome = await analyzeVideoVisuals({ videoId, force: false });
          const usageAfter = await prisma.guideVisualUsageLog.count({
            where: { success: true },
          });
          const jobsAfter = await prisma.guideVisualAnalysisJob.count({
            where: { videoId },
          });
          // eslint-disable-next-line no-console
          console.log(
            JSON.stringify({
              phase: "cache-check",
              status: outcome.status,
              jobId: outcome.jobId,
              usageLogDelta: usageAfter - usageBefore,
              jobDelta: jobsAfter - jobsBefore,
              control,
            }),
          );
          expect(["cache_hit", "already_analyzed"]).toContain(outcome.status);
          expect(usageAfter - usageBefore).toBe(0);
          expect(jobsAfter - jobsBefore).toBe(0);
          return;
        }

        throw new Error(`unknown CANARY_CMD=${cmd}`);
      } finally {
        await prisma.$disconnect();
      }
    },
    600_000,
  );
});
