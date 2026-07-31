import "server-only";

import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/db";
import {
  lockYoutubeAutomationControl,
  YOUTUBE_AUTOMATION_CONTROL_ID,
} from "./automation-control";
import { youtubeAutomationFlags } from "./feature-flags";

export async function getYoutubeAutomationAdminOverview() {
  const [runs, items, circuits, leases, control] = await Promise.all([
    prisma.guidePipelineRun.findMany({
      orderBy: { startedAt: "desc" },
      take: 25,
      select: {
        id: true,
        pipelineRunId: true,
        trigger: true,
        mode: true,
        status: true,
        dryRun: true,
        policyVersion: true,
        startedAt: true,
        completedAt: true,
      },
    }),
    prisma.guidePipelineItem.findMany({
      orderBy: { updatedAt: "desc" },
      take: 100,
      select: {
        id: true,
        runId: true,
        activeRunId: true,
        lastRunId: true,
        videoId: true,
        characterId: true,
        status: true,
        stateVersion: true,
        leaseOwner: true,
        leaseVersion: true,
        attempts: true,
        maxAttempts: true,
        nextRetryAt: true,
        blockCode: true,
        safeErrorCode: true,
        updatedAt: true,
      },
    }),
    prisma.guideProviderCircuit.findMany({
      orderBy: { providerId: "asc" },
      select: {
        providerId: true,
        state: true,
        failureCount: true,
        lastErrorCode: true,
        openedAt: true,
        openUntil: true,
        probeOwner: true,
        probeToken: true,
        probeAcquiredAt: true,
        probeExpiresAt: true,
        stateVersion: true,
        updatedAt: true,
      },
    }),
    prisma.guidePipelineLease.findMany({
      where: { leaseExpiresAt: { gt: new Date() } },
      orderBy: { leaseExpiresAt: "asc" },
      take: 50,
      select: {
        lockKey: true,
        leaseOwner: true,
        leaseAcquiredAt: true,
        leaseExpiresAt: true,
        leaseVersion: true,
      },
    }),
    prisma.guideAutomationControl.findUnique({
      where: { id: "youtube-guide" },
      select: {
        emergencyStopped: true,
        reason: true,
        version: true,
        updatedAt: true,
      },
    }),
  ]);
  return {
    flags: youtubeAutomationFlags(),
    control: control ?? {
      emergencyStopped: true,
      reason: "CONTROL_ROW_MISSING",
      version: -1,
      updatedAt: null,
    },
    runs,
    items,
    circuits,
    leases,
  };
}

export async function setYoutubeAutomationEmergencyStop(input: {
  emergencyStopped: boolean;
  reason: string;
}) {
  const reason = input.reason.trim().slice(0, 200);
  const now = new Date();
  return prisma.$transaction(async (transaction) => {
    await transaction.$executeRaw(Prisma.sql`
      INSERT INTO "GuideAutomationControl"
        ("id", "emergencyStopped", "reason", "version", "updatedAt")
      VALUES
        (${YOUTUBE_AUTOMATION_CONTROL_ID}, true, 'CONTROL_INITIALIZING', 0, ${now})
      ON CONFLICT ("id") DO NOTHING
    `);
    await lockYoutubeAutomationControl(transaction);
    const control = await transaction.guideAutomationControl.update({
      where: { id: YOUTUBE_AUTOMATION_CONTROL_ID },
      data: {
        emergencyStopped: input.emergencyStopped,
        reason,
        version: { increment: 1 },
        updatedAt: now,
      },
    });
    await transaction.guideAdminAuditLog.create({
      data: {
        actor: "admin",
        action: "youtube_automation_emergency_stop",
        status: "ok",
        detail: JSON.stringify({
          emergencyStopped: control.emergencyStopped,
          version: control.version,
        }),
      },
    });
    return control;
  });
}
