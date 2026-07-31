import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import {
  claimPipelineItem,
  releasePipelineItemClaim,
  renewPipelineItemClaim,
  updatePipelineItemWithClaim,
  type ItemLeaseClaim,
} from "@/lib/build-guides/automation/pipeline-item-lease";
import { transitionPipelineItem } from "@/lib/build-guides/automation/pipeline-item-store";
import { automationHash } from "@/lib/build-guides/automation/idempotency";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTAUDITLEASE00000001";
let sequence = 0;

describe.runIf(runDbTests)("YouTube automation audit item lease", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Audit item lease",
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    });
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("grants one worker and the loser leaves item status unchanged", async () => {
    const fixture = await createItem("lease-race");
    const now = new Date("2026-07-31T00:00:00.000Z");
    const [first, second] = await Promise.all([
      claimPipelineItem({
        itemId: fixture.itemId,
        runDatabaseId: fixture.runDatabaseId,
        pipelineRunId: fixture.pipelineRunId,
        workerId: "worker-a",
        now,
      }),
      claimPipelineItem({
        itemId: fixture.itemId,
        runDatabaseId: fixture.runDatabaseId,
        pipelineRunId: fixture.pipelineRunId,
        workerId: "worker-b",
        now,
      }),
    ]);
    const winners = [first, second].filter(
      (claim): claim is ItemLeaseClaim => claim !== null,
    );
    expect(winners).toHaveLength(1);
    const firstWinner = winners[0]!;
    await expect(
      prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: fixture.itemId },
        select: { status: true, attempts: true },
      }),
    ).resolves.toEqual({ status: "DISCOVERED", attempts: 0 });
    await releasePipelineItemClaim({ claim: firstWinner });
    const reclaimed = await claimPipelineItem({
      itemId: fixture.itemId,
      runDatabaseId: fixture.runDatabaseId,
      pipelineRunId: fixture.pipelineRunId,
      workerId: "worker-c",
      now: new Date(now.getTime() + 1),
    });
    expect(reclaimed).not.toBeNull();
    expect(reclaimed!.lease.leaseVersion).toBeGreaterThan(
      firstWinner.lease.leaseVersion,
    );
    await expect(
      prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: fixture.itemId },
        select: { leaseVersion: true },
      }),
    ).resolves.toEqual({ leaseVersion: reclaimed!.lease.leaseVersion });
    await releasePipelineItemClaim({ claim: reclaimed! });
  });

  it("does not claim a retry before nextRetryAt", async () => {
    const fixture = await createItem("lease-next-retry", {
      status: "RETRYABLE_ERROR",
      nextRetryAt: new Date("2026-07-31T01:01:00.000Z"),
    });
    const result = await claimPipelineItem({
      itemId: fixture.itemId,
      runDatabaseId: fixture.runDatabaseId,
      pipelineRunId: fixture.pipelineRunId,
      workerId: "worker-early",
      now: new Date("2026-07-31T01:00:00.000Z"),
    });
    expect(result).toBeNull();
    const releasedLease = await prisma.guidePipelineLease.findUniqueOrThrow({
      where: { lockKey: `pipeline-item:${fixture.itemId}` },
      select: { leaseAcquiredAt: true, leaseExpiresAt: true },
    });
    expect(releasedLease.leaseExpiresAt.getTime()).toBeLessThanOrEqual(
      releasedLease.leaseAcquiredAt.getTime(),
    );
  });

  it("rejects stale writes, renew conflicts, and non-owner release", async () => {
    const fixture = await createItem("lease-fence");
    const started = new Date("2026-07-31T02:00:00.000Z");
    const first = await claimPipelineItem({
      itemId: fixture.itemId,
      runDatabaseId: fixture.runDatabaseId,
      pipelineRunId: fixture.pipelineRunId,
      workerId: "worker-old",
      now: started,
    });
    if (!first) throw new Error("fixtureClaimFailed");
    const second = await claimPipelineItem({
      itemId: fixture.itemId,
      runDatabaseId: fixture.runDatabaseId,
      pipelineRunId: fixture.pipelineRunId,
      workerId: "worker-new",
      now: new Date(started.getTime() + 60_000),
    });
    if (!second) throw new Error("fixtureReclaimFailed");

    await expect(
      updatePipelineItemWithClaim({
        claim: first,
        now: new Date(started.getTime() + 60_001),
        data: { safeErrorCode: "STALE_MUST_NOT_WRITE" },
      }),
    ).rejects.toThrow(/PIPELINE_ITEM_(?:LEASE_LOST|FENCE_STALE)/);
    await expect(
      transitionPipelineItem({
        claim: first,
        now: new Date(started.getTime() + 60_001),
        toStatus: "RETRYABLE_ERROR",
        safeCode: "STALE_MUST_NOT_TRANSITION",
      }),
    ).rejects.toThrow(/PIPELINE_ITEM_(?:LEASE_LOST|FENCE_STALE)/);
    await releasePipelineItemClaim({ claim: first });
    await expect(
      prisma.guidePipelineLease.findUniqueOrThrow({
        where: { lockKey: `pipeline-item:${fixture.itemId}` },
        select: { leaseOwner: true, leaseVersion: true },
      }),
    ).resolves.toEqual({
      leaseOwner: second.lease.leaseOwner,
      leaseVersion: second.lease.leaseVersion,
    });

    const fakeOwner: ItemLeaseClaim = {
      ...second,
      lease: {
        ...second.lease,
        leaseOwner: `${fixture.pipelineRunId}:intruder`,
      },
    };
    await releasePipelineItemClaim({ claim: fakeOwner });
    await expect(
      prisma.guidePipelineLease.findUniqueOrThrow({
        where: { lockKey: `pipeline-item:${fixture.itemId}` },
        select: { leaseOwner: true },
      }),
    ).resolves.toEqual({ leaseOwner: second.lease.leaseOwner });

    const left = cloneClaim(second);
    const right = cloneClaim(second);
    const renewals = await Promise.all([
      renewPipelineItemClaim({
        claim: left,
        now: new Date(started.getTime() + 60_100),
      }),
      renewPipelineItemClaim({
        claim: right,
        now: new Date(started.getTime() + 60_100),
      }),
    ]);
    expect(renewals.filter(Boolean)).toHaveLength(1);
    const renewed = renewals[0] ? left : right;
    await releasePipelineItemClaim({ claim: renewed });
  });
});

function cloneClaim(claim: ItemLeaseClaim): ItemLeaseClaim {
  return { ...claim, lease: { ...claim.lease } };
}

async function createItem(
  label: string,
  state: { status?: string; nextRetryAt?: Date } = {},
) {
  const token = ++sequence;
  const videoId = `leasev${token.toString().padStart(5, "0")}`;
  const pipelineRunId = `audit-${label}-${token}`;
  await prisma.guideVideo.create({
    data: {
      videoId,
      channelId,
      title: label,
      privacyStatus: "public",
      metadataHash: automationHash("lease-meta", token),
      sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
    },
  });
  const run = await prisma.guidePipelineRun.create({
    data: {
      pipelineRunId,
      idempotencyKey: automationHash("lease-run", token),
      trigger: "test",
      dryRun: false,
      policyVersion: "lease-test",
      policyHash: automationHash("lease-policy", token),
    },
  });
  const item = await prisma.guidePipelineItem.create({
    data: {
      runId: run.id,
      lastRunId: run.id,
      videoId,
      characterId: `lease-character-${token}`,
      discoveryKey: automationHash("lease-discovery", token),
      status: state.status ?? "DISCOVERED",
      nextRetryAt: state.nextRetryAt,
    },
  });
  return { itemId: item.id, runDatabaseId: run.id, pipelineRunId };
}

async function cleanup(): Promise<void> {
  await prisma.guidePipelineLease.deleteMany({
    where: { lockKey: { startsWith: "pipeline-item:" } },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: { pipelineRunId: { startsWith: "audit-lease-" } },
  });
  await prisma.guideVideo.deleteMany({ where: { channelId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
