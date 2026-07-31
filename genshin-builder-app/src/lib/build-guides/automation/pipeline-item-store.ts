import "server-only";

import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/db";
import { automationHash } from "./idempotency";
import {
  assertPipelineItemClaim,
  type ItemLeaseClaim,
} from "./pipeline-item-lease";
import {
  assertPipelineTransition,
  type PipelineStatus,
} from "./state-machine";

export async function transitionPipelineItem(input: {
  claim: ItemLeaseClaim;
  now: Date;
  toStatus: PipelineStatus;
  safeCode?: string;
  blockCode?: string;
  resumeStatus?: PipelineStatus;
  nextRetryAt?: Date | null;
  safeDetail?: Readonly<Record<string, string | number | boolean | null>>;
}) {
  const result = await prisma.$transaction(async (transaction) => {
    await assertPipelineItemClaim(transaction, input.claim, input.now);
    const rows = await transaction.$queryRaw<
      Array<{
        id: string;
        videoId: string;
        status: string;
        attempts: number;
      }>
    >(Prisma.sql`
      SELECT "id", "videoId", "status", "attempts"
      FROM "GuidePipelineItem"
      WHERE "id" = ${input.claim.itemId}
      FOR UPDATE
    `);
    const item = rows[0];
    if (!item) throw new Error("pipelineItemNotFound");
    const fromStatus = item.status as PipelineStatus;
    assertPipelineTransition(fromStatus, input.toStatus);
    const actionKey = automationHash("youtube-pipeline-transition-v2", {
      itemId: item.id,
      runId: input.claim.runDatabaseId,
      fromStatus,
      toStatus: input.toStatus,
      attempt: item.attempts,
      stateVersion: input.claim.stateVersion,
    });
    const update = await transaction.guidePipelineItem.updateMany({
      where: {
        id: item.id,
        status: fromStatus,
        attempts: item.attempts,
        activeRunId: input.claim.runDatabaseId,
        leaseOwner: input.claim.lease.leaseOwner,
        leaseVersion: input.claim.lease.leaseVersion,
        stateVersion: input.claim.stateVersion,
      },
      data: {
        status: input.toStatus,
        blockCode: input.blockCode ?? "",
        safeErrorCode: input.safeCode ?? "",
        resumeStatus: input.resumeStatus ?? "",
        nextRetryAt: input.nextRetryAt,
        ...(input.toStatus === "RETRYABLE_ERROR"
          ? { attempts: { increment: 1 } }
          : {}),
        stateVersion: { increment: 1 },
      },
    });
    if (update.count !== 1) throw new Error("pipelineItemTransitionConflict");
    await transaction.guidePipelineEvent.create({
      data: {
        actionKey,
        runId: input.claim.runDatabaseId,
        itemId: item.id,
        fromStatus,
        toStatus: input.toStatus,
        safeCode: input.safeCode ?? "",
        detailPayload: JSON.stringify({
          videoId: item.videoId,
          ...(input.safeDetail ?? {}),
        }).slice(0, 4_000),
      },
    });
    const updated = await transaction.guidePipelineItem.findUniqueOrThrow({
      where: { id: item.id },
    });
    return updated;
  });
  input.claim.stateVersion += 1;
  return result;
}
