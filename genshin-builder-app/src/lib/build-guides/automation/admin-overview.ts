import "server-only";

import { prisma } from "@/lib/db";
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
        videoId: true,
        status: true,
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
        halfOpenProbeAt: true,
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
      emergencyStopped: false,
      reason: "",
      version: 0,
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
    const control = await transaction.guideAutomationControl.upsert({
      where: { id: "youtube-guide" },
      create: {
        id: "youtube-guide",
        emergencyStopped: input.emergencyStopped,
        reason,
        version: 1,
        updatedAt: now,
      },
      update: {
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
