/**
 * Read-only recheck after Emergency should be ON again.
 * COVERAGE_RECOVERY_OPS_RECHECK_LIVE=1
 * No recovery / AI / publish / batch / Emergency mutation.
 */
import { describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { readGlobalAiEmergencyControl } from "@/lib/ai/global-ai-emergency";
import { getCoverageMetrics } from "@/lib/build-guides/visual-coverage";
import { writeFileSync } from "node:fs";

const enabled = process.env.COVERAGE_RECOVERY_OPS_RECHECK_LIVE === "1";

// Previous ops verification window (approx): 2026-08-08T14:43Z
const PREV_OPS_AT = new Date("2026-08-08T14:40:00.000Z");

const PREV_SNAPSHOT = {
  totalCharacters: 122,
  coveredCharacters: 15,
  uncoveredCharacters: 107,
  recoverablePostProcessFailures: 0,
  eligiblePendingVideos: 0,
} as const;

describe.skipIf(!enabled)("Coverage Recovery Ops recheck (read-only)", () => {
  it(
    "Emergency ON + idle AI + stable coverage",
    async () => {
      const emergency = await readGlobalAiEmergencyControl();
      const controlRow = await prisma.guideAutomationControl.findUnique({
        where: { id: "youtube-guide" },
        select: {
          emergencyStopped: true,
          reason: true,
          version: true,
          updatedAt: true,
        },
      });

      const recentEmergencyAudits = await prisma.guideAdminAuditLog.findMany({
        where: {
          action: "youtube_automation_emergency_stop",
          createdAt: { gte: PREV_OPS_AT },
        },
        orderBy: { createdAt: "desc" },
        take: 5,
        select: {
          actor: true,
          action: true,
          status: true,
          detail: true,
          createdAt: true,
        },
      });

      const jobStatusCounts = await prisma.guideVisualAnalysisJob.groupBy({
        by: ["status"],
        _count: { _all: true },
      });
      const runningJobs = await prisma.guideVisualAnalysisJob.count({
        where: { status: { in: ["running", "in_progress", "processing"] } },
      });
      const pendingRetryJobs = await prisma.guideVisualAnalysisJob.count({
        where: {
          status: {
            in: ["pending", "queued", "retry", "retrying", "waiting"],
          },
        },
      });

      const pipelineRunning = await prisma.guidePipelineRun.count({
        where: { status: { in: ["running", "pending", "queued"] } },
      });
      const pipelineItemPending = await prisma.guidePipelineItem.count({
        where: {
          status: {
            in: ["pending", "queued", "running", "retry", "retrying"],
          },
        },
      });

      const usageSincePrev = await prisma.guideVisualUsageLog.count({
        where: { createdAt: { gte: PREV_OPS_AT } },
      });
      const usageSincePrevByProvider = await prisma.guideVisualUsageLog.groupBy({
        by: ["providerId"],
        where: { createdAt: { gte: PREV_OPS_AT } },
        _count: { _all: true },
      });

      const publishedSincePrev = await prisma.characterBuildRecommendation.count({
        where: {
          status: "published",
          publishedAt: { gte: PREV_OPS_AT },
        },
      });
      // Also catch status flips without publishedAt change
      const publishedUpdatedSincePrev =
        await prisma.characterBuildRecommendation.count({
          where: {
            status: "published",
            updatedAt: { gte: PREV_OPS_AT },
          },
        });

      const coverage = await getCoverageMetrics({ eligibleLimit: 3 });

      const snapshotDiff = {
        totalCharacters:
          coverage.totalCharacters - PREV_SNAPSHOT.totalCharacters,
        coveredCharacters:
          coverage.coveredCharacters - PREV_SNAPSHOT.coveredCharacters,
        uncoveredCharacters:
          coverage.uncoveredCharacters - PREV_SNAPSHOT.uncoveredCharacters,
        recoverablePostProcessFailures:
          coverage.recoverablePostProcessFailures -
          PREV_SNAPSHOT.recoverablePostProcessFailures,
        eligiblePendingVideos:
          coverage.eligiblePendingVideos - PREV_SNAPSHOT.eligiblePendingVideos,
      };

      const latestAudit = recentEmergencyAudits[0] ?? null;
      let auditDetail: Record<string, unknown> | null = null;
      if (latestAudit?.detail) {
        try {
          auditDetail = JSON.parse(latestAudit.detail) as Record<string, unknown>;
        } catch {
          auditDetail = { rawLen: latestAudit.detail.length };
        }
      }

      const adminSafetySwitchUpdate =
        latestAudit != null &&
        latestAudit.actor === "admin" &&
        latestAudit.action === "youtube_automation_emergency_stop" &&
        auditDetail?.emergencyStopped === true;

      const report = {
        emergency: {
          emergencyStopped: emergency.emergencyStopped,
          version: emergency.version,
          reasonLen: (controlRow?.reason ?? emergency.reason ?? "").length,
          updatedAt: controlRow?.updatedAt?.toISOString() ?? null,
          adminSafetySwitchUpdate,
          latestAudit: latestAudit
            ? {
                actor: latestAudit.actor,
                status: latestAudit.status,
                createdAt: latestAudit.createdAt.toISOString(),
                detailEmergencyStopped: auditDetail?.emergencyStopped ?? null,
                detailVersion: auditDetail?.version ?? null,
              }
            : null,
        },
        jobs: {
          statusCounts: Object.fromEntries(
            jobStatusCounts.map((r) => [r.status, r._count._all]),
          ),
          running: runningJobs,
          pendingRetry: pendingRetryJobs,
          pipelineRunning,
          pipelineItemPending,
        },
        aiUsageSincePrevOps: {
          total: usageSincePrev,
          byProvider: usageSincePrevByProvider.map((r) => ({
            providerId: r.providerId,
            count: r._count._all,
          })),
        },
        publishSincePrevOps: {
          publishedAtGte: publishedSincePrev,
          updatedAtGteWhilePublished: publishedUpdatedSincePrev,
        },
        coverageSnapshot: {
          totalCharacters: coverage.totalCharacters,
          coveredCharacters: coverage.coveredCharacters,
          uncoveredCharacters: coverage.uncoveredCharacters,
          publishedCharacters: coverage.publishedCharacters,
          pendingReviewCharacters: coverage.pendingReviewCharacters,
          evidenceOnlyCharacters: coverage.evidenceOnlyCharacters,
          recoverablePostProcessFailures:
            coverage.recoverablePostProcessFailures,
          eligiblePendingVideos: coverage.eligiblePendingVideos,
          remainingEligibleVideos: coverage.remainingEligibleVideos,
          titleResolutionFailedVideos: coverage.titleResolutionFailedVideos,
        },
        snapshotDiffVsPrevOps: snapshotDiff,
        gate: {
          emergencyOn: emergency.emergencyStopped === true,
          versionGt9: emergency.version > 9,
          adminSafetySwitch: adminSafetySwitchUpdate,
          runningZero: runningJobs === 0 && pipelineRunning === 0,
          pendingRetryZero:
            pendingRetryJobs === 0 && pipelineItemPending === 0,
          aiUsageDeltaZero: usageSincePrev === 0,
          publishDeltaZero: publishedSincePrev === 0,
          coverageStableOrExplained: true as boolean,
        },
      };

      const unexpectedCoverageChange = Object.entries(snapshotDiff).some(
        ([, v]) => v !== 0,
      );
      report.gate.coverageStableOrExplained = !unexpectedCoverageChange;

      writeFileSync(
        "scripts/_tmp-coverage-recovery-ops-recheck.json",
        JSON.stringify(report, null, 2),
        "utf8",
      );
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(report, null, 2));

      expect(emergency.emergencyStopped).toBe(true);
      expect(emergency.version).toBeGreaterThan(9);
      expect(runningJobs).toBe(0);
      expect(pendingRetryJobs).toBe(0);
      expect(pipelineRunning).toBe(0);
      expect(pipelineItemPending).toBe(0);
      expect(usageSincePrev).toBe(0);
      expect(publishedSincePrev).toBe(0);

      const pass =
        report.gate.emergencyOn &&
        report.gate.versionGt9 &&
        report.gate.runningZero &&
        report.gate.pendingRetryZero &&
        report.gate.aiUsageDeltaZero &&
        report.gate.publishDeltaZero &&
        report.gate.coverageStableOrExplained;

      if (!pass) {
        expect.fail(`Recheck gate FAIL: ${JSON.stringify(report.gate)}`);
      }
    },
    60_000,
  );
});
