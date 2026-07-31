import "server-only";

import { prisma } from "@/lib/db";
import { automationHash } from "./idempotency";
import {
  assertPipelineTransition,
  type PipelineStatus,
} from "./state-machine";

export async function transitionPipelineItem(input: {
  itemId: string;
  toStatus: PipelineStatus;
  safeCode?: string;
  blockCode?: string;
  resumeStatus?: PipelineStatus;
  nextRetryAt?: Date | null;
  safeDetail?: Readonly<Record<string, string | number | boolean | null>>;
}) {
  const item = await prisma.guidePipelineItem.findUnique({
    where: { id: input.itemId },
    select: {
      id: true,
      runId: true,
      videoId: true,
      status: true,
      attempts: true,
      discoveryKey: true,
    },
  });
  if (!item) throw new Error("pipelineItemNotFound");
  const fromStatus = item.status as PipelineStatus;
  assertPipelineTransition(fromStatus, input.toStatus);
  const actionKey = automationHash("youtube-pipeline-transition-v1", {
    itemId: item.id,
    fromStatus,
    toStatus: input.toStatus,
    attempt: item.attempts,
  });
  return prisma.$transaction(async (transaction) => {
    const update = await transaction.guidePipelineItem.updateMany({
      where: { id: item.id, status: fromStatus, attempts: item.attempts },
      data: {
        status: input.toStatus,
        blockCode: input.blockCode ?? "",
        safeErrorCode: input.safeCode ?? "",
        resumeStatus: input.resumeStatus ?? "",
        nextRetryAt: input.nextRetryAt,
        ...(input.toStatus === "RETRYABLE_ERROR"
          ? { attempts: { increment: 1 } }
          : {}),
      },
    });
    if (update.count !== 1) throw new Error("pipelineItemTransitionConflict");
    await transaction.guidePipelineEvent.create({
      data: {
        actionKey,
        runId: item.runId,
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
    return transaction.guidePipelineItem.findUniqueOrThrow({
      where: { id: item.id },
    });
  });
}
