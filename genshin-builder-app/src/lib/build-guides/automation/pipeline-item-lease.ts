import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import {
  acquirePipelineLease,
  releasePipelineLease,
  renewPipelineLease,
  type PipelineLease,
} from "./lease-store";

export type ItemLeaseClaim = {
  itemId: string;
  runDatabaseId: string;
  pipelineRunId: string;
  workerId: string;
  stateVersion: number;
  lease: PipelineLease;
};

export const PIPELINE_ITEM_LEASE_TTL_MS = 60_000;

export async function claimPipelineItem(input: {
  itemId: string;
  runDatabaseId: string;
  pipelineRunId: string;
  workerId: string;
  now: Date;
  client?: PrismaClient;
}): Promise<ItemLeaseClaim | null> {
  const client = input.client ?? prisma;
  const lease = await acquirePipelineLease({
    lockKey: `pipeline-item:${input.itemId}`,
    leaseOwner: `${input.pipelineRunId}:${input.workerId}`,
    now: input.now,
    ttlMs: PIPELINE_ITEM_LEASE_TTL_MS,
    client,
  });
  if (!lease) return null;
  let completed = false;
  try {
    const updated = await client.guidePipelineItem.updateMany({
      where: {
        id: input.itemId,
        OR: [
          { nextRetryAt: null },
          { nextRetryAt: { lte: input.now } },
        ],
      },
      data: {
        activeRunId: input.runDatabaseId,
        lastRunId: input.runDatabaseId,
        leaseOwner: lease.leaseOwner,
        leaseVersion: lease.leaseVersion,
        stateVersion: { increment: 1 },
      },
    });
    if (updated.count !== 1) return null;
    const item = await client.guidePipelineItem.findUniqueOrThrow({
      where: { id: input.itemId },
      select: { stateVersion: true },
    });
    const claim = {
      itemId: input.itemId,
      runDatabaseId: input.runDatabaseId,
      pipelineRunId: input.pipelineRunId,
      workerId: input.workerId,
      stateVersion: item.stateVersion,
      lease,
    };
    completed = true;
    return claim;
  } finally {
    if (!completed) {
      await client.guidePipelineItem.updateMany({
        where: {
          id: input.itemId,
          leaseOwner: lease.leaseOwner,
          leaseVersion: lease.leaseVersion,
        },
        data: {
          leaseOwner: "",
          stateVersion: { increment: 1 },
        },
      }).catch(() => undefined);
      await releasePipelineLease({ lease, client }).catch(() => false);
    }
  }
}

export async function renewPipelineItemClaim(input: {
  claim: ItemLeaseClaim;
  now: Date;
  client?: PrismaClient;
}): Promise<boolean> {
  const client = input.client ?? prisma;
  const renewed = await renewPipelineLease({
    lease: input.claim.lease,
    now: input.now,
    ttlMs: PIPELINE_ITEM_LEASE_TTL_MS,
    client,
  });
  if (!renewed) return false;
  const update = await client.guidePipelineItem.updateMany({
    where: {
      id: input.claim.itemId,
      activeRunId: input.claim.runDatabaseId,
      leaseOwner: input.claim.lease.leaseOwner,
      leaseVersion: input.claim.lease.leaseVersion,
      stateVersion: input.claim.stateVersion,
    },
    data: { leaseVersion: renewed.leaseVersion },
  });
  if (update.count !== 1) {
    await releasePipelineLease({ lease: renewed, client }).catch(() => false);
    return false;
  }
  input.claim.lease = renewed;
  return true;
}

export async function releasePipelineItemClaim(input: {
  claim: ItemLeaseClaim;
  client?: PrismaClient;
}): Promise<void> {
  const client = input.client ?? prisma;
  const cleared = await client.guidePipelineItem.updateMany({
    where: {
      id: input.claim.itemId,
      activeRunId: input.claim.runDatabaseId,
      leaseOwner: input.claim.lease.leaseOwner,
      leaseVersion: input.claim.lease.leaseVersion,
      stateVersion: input.claim.stateVersion,
    },
    data: {
      leaseOwner: "",
      stateVersion: { increment: 1 },
    },
  });
  if (cleared.count === 1) input.claim.stateVersion += 1;
  await releasePipelineLease({ lease: input.claim.lease, client }).catch(
    () => false,
  );
}

export async function assertPipelineItemClaim(
  transaction: Prisma.TransactionClient,
  claim: ItemLeaseClaim,
  now: Date,
): Promise<void> {
  const rows = await transaction.$queryRaw<Array<{ present: number }>>(
    Prisma.sql`
      SELECT 1 AS "present"
      FROM "GuidePipelineLease"
      WHERE
        "lockKey" = ${claim.lease.lockKey}
        AND "leaseOwner" = ${claim.lease.leaseOwner}
        AND "leaseVersion" = ${claim.lease.leaseVersion}
        AND "leaseExpiresAt" > ${now}
      FOR SHARE
    `,
  );
  if (rows.length !== 1) throw new Error("PIPELINE_ITEM_LEASE_LOST");
  const item = await transaction.guidePipelineItem.findUnique({
    where: { id: claim.itemId },
    select: {
      activeRunId: true,
      leaseOwner: true,
      leaseVersion: true,
      stateVersion: true,
    },
  });
  if (
    !item ||
    item.activeRunId !== claim.runDatabaseId ||
    item.leaseOwner !== claim.lease.leaseOwner ||
    item.leaseVersion !== claim.lease.leaseVersion ||
    item.stateVersion !== claim.stateVersion
  ) {
    throw new Error("PIPELINE_ITEM_FENCE_STALE");
  }
}

type FencedItemData = Partial<{
  characterId: string;
  transcriptId: string | null;
  transcriptHash: string;
  analysisIdempotencyKey: string | null;
  publicationKey: string | null;
  analyzerVersion: string;
  promptVersion: string;
  schemaVersion: string;
  qualityPayload: string;
  canonicalAnalysisPayload: string;
  validationHash: string;
  snapshotPayload: string;
  policyHash: string;
  blockCode: string;
  safeErrorCode: string;
  resumeStatus: string;
  nextRetryAt: Date | null;
}>;

export async function updatePipelineItemWithClaim(input: {
  claim: ItemLeaseClaim;
  now: Date;
  data: FencedItemData;
  client?: PrismaClient;
}): Promise<void> {
  const client = input.client ?? prisma;
  await client.$transaction(async (transaction) => {
    await assertPipelineItemClaim(transaction, input.claim, input.now);
    const update = await transaction.guidePipelineItem.updateMany({
      where: {
        id: input.claim.itemId,
        activeRunId: input.claim.runDatabaseId,
        leaseOwner: input.claim.lease.leaseOwner,
        leaseVersion: input.claim.lease.leaseVersion,
        stateVersion: input.claim.stateVersion,
      },
      data: { ...input.data, stateVersion: { increment: 1 } },
    });
    if (update.count !== 1) throw new Error("PIPELINE_ITEM_FENCE_STALE");
  });
  input.claim.stateVersion += 1;
}
