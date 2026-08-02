import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { readYoutubeAutomationControl } from "./automation-control";
import { transcriptIdentityKey } from "./idempotency";
import {
  assertPipelineItemClaim,
  type ItemLeaseClaim,
} from "./pipeline-item-lease";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";
import type { NormalizedTranscript } from "./transcript-normalize";

export type TranscriptPersistenceResult =
  | { stored: true; transcriptId: string; duplicate: boolean }
  | {
      stored: false;
      blockCode: "BLOCKED_DUPLICATE_TRANSCRIPT_CONTENT";
      existingTranscriptId: string;
    };

export async function persistNormalizedTranscript(input: {
  transcript: NormalizedTranscript;
  now: Date;
  itemClaim?: ItemLeaseClaim;
  client?: PrismaClient;
}): Promise<TranscriptPersistenceResult> {
  const client = input.client ?? prisma;
  const { transcript } = input;
  const identityKey = transcriptIdentityKey({
    videoId: transcript.videoId,
    language: transcript.language,
    providerId: transcript.providerId,
    sourceTrackId: transcript.sourceTrackId,
    transcriptHash: transcript.transcriptHash,
  });
  const retentionExpiresAt = new Date(
    input.now.getTime() +
      YOUTUBE_AUTOMATION_POLICY.transcriptRetentionDays * 86_400_000,
  );
  const result = await client.$transaction(async (transaction) => {
    const existingByHash = await transaction.guideTranscript.findUnique({
      where: { transcriptHash: transcript.transcriptHash },
      select: { id: true, videoId: true },
    });
    if (existingByHash) {
      if (existingByHash.videoId !== transcript.videoId) {
        return {
          result: {
            stored: false as const,
            blockCode: "BLOCKED_DUPLICATE_TRANSCRIPT_CONTENT" as const,
            existingTranscriptId: existingByHash.id,
          },
          claimAdvanced: false,
        };
      }
      await transaction.$queryRaw(Prisma.sql`
        SELECT "id"
        FROM "GuideTranscript"
        WHERE "id" = ${existingByHash.id}
        FOR KEY SHARE
      `);
      await linkTranscriptToClaim(transaction, {
        claim: input.itemClaim,
        transcriptId: existingByHash.id,
        transcriptHash: transcript.transcriptHash,
        now: input.now,
      });
      return {
        result: {
          stored: true as const,
          transcriptId: existingByHash.id,
          duplicate: true,
        },
        claimAdvanced: Boolean(input.itemClaim),
      };
    }
    const existing = await transaction.guideTranscript.findUnique({
      where: { identityKey },
      select: { id: true },
    });
    if (existing) {
      await transaction.$queryRaw(Prisma.sql`
        SELECT "id"
        FROM "GuideTranscript"
        WHERE "id" = ${existing.id}
        FOR KEY SHARE
      `);
      await linkTranscriptToClaim(transaction, {
        claim: input.itemClaim,
        transcriptId: existing.id,
        transcriptHash: transcript.transcriptHash,
        now: input.now,
      });
      return {
        result: {
          stored: true as const,
          transcriptId: existing.id,
          duplicate: true,
        },
        claimAdvanced: Boolean(input.itemClaim),
      };
    }
    const created = await transaction.guideTranscript.create({
      data: {
        videoId: transcript.videoId,
        identityKey,
        transcriptHash: transcript.transcriptHash,
        providerId: transcript.providerId,
        language: transcript.language,
        trackKind: transcript.trackKind,
        sourceTrackId: transcript.sourceTrackId,
        segmentCount: transcript.segments.length,
        fetchedAt: transcript.fetchedAt,
        retentionExpiresAt,
        segments: {
          create: transcript.segments.map((segment) => ({
            segmentIndex: segment.index,
            segmentKey: segment.segmentKey,
            startSeconds: segment.startSeconds,
            durationSeconds: segment.durationSeconds,
            text: segment.text,
            textHash: segment.textHash,
          })),
        },
      },
      select: { id: true },
    });
    await linkTranscriptToClaim(transaction, {
      claim: input.itemClaim,
      transcriptId: created.id,
      transcriptHash: transcript.transcriptHash,
      now: input.now,
    });
    return {
      result: {
        stored: true as const,
        transcriptId: created.id,
        duplicate: false,
      },
      claimAdvanced: Boolean(input.itemClaim),
    };
  });
  if (result.claimAdvanced && input.itemClaim) {
    input.itemClaim.stateVersion += 1;
  }
  return result.result;
}

/**
 * Deletes only expired transcripts that no in-flight/retryable item can use.
 * Transcript row locking and lease rechecks make cleanup safe against workers.
 */
export async function deleteExpiredTranscripts(input: {
  now: Date;
  limit?: number;
  client?: PrismaClient;
}): Promise<number> {
  const client = input.client ?? prisma;
  const limit = Math.max(1, Math.min(1_000, Math.trunc(input.limit ?? 100)));
  const control = await readYoutubeAutomationControl(client);
  if (control.emergencyStopped) return 0;
  return client.$transaction(async (transaction) => {
    const expired = await transaction.guideTranscript.findMany({
      where: {
        retentionExpiresAt: { lte: input.now },
        deletedAt: null,
      },
      select: { id: true },
      orderBy: { retentionExpiresAt: "asc" },
      take: limit,
    });
    let deleted = 0;
    for (const transcript of expired) {
      await transaction.$queryRaw(Prisma.sql`
        SELECT "id"
        FROM "GuideTranscript"
        WHERE "id" = ${transcript.id}
        FOR UPDATE
      `);
      const items = await transaction.guidePipelineItem.findMany({
        where: { transcriptId: transcript.id },
        select: {
          id: true,
          status: true,
          nextRetryAt: true,
        },
      });
      const terminal = new Set([
        "PUBLISHED",
        "REVIEW_REQUIRED",
        "BLOCKED",
      ]);
      if (
        items.some(
          (item) =>
            !terminal.has(item.status) ||
            item.nextRetryAt !== null,
        )
      ) {
        continue;
      }
      const activeLease =
        items.length === 0
          ? null
          : await transaction.guidePipelineLease.findFirst({
              where: {
                lockKey: {
                  in: items.map((item) => `pipeline-item:${item.id}`),
                },
                leaseExpiresAt: { gt: input.now },
              },
              select: { lockKey: true },
            });
      if (activeLease) continue;
      const result = await transaction.guideTranscript.deleteMany({
        where: {
          id: transcript.id,
          retentionExpiresAt: { lte: input.now },
          deletedAt: null,
        },
      });
      deleted += result.count;
    }
    return deleted;
  });
}

async function linkTranscriptToClaim(
  transaction: Prisma.TransactionClient,
  input: {
    claim?: ItemLeaseClaim;
    transcriptId: string;
    transcriptHash: string;
    now: Date;
  },
): Promise<void> {
  if (!input.claim) return;
  await assertPipelineItemClaim(transaction, input.claim, input.now);
  const update = await transaction.guidePipelineItem.updateMany({
    where: {
      id: input.claim.itemId,
      activeRunId: input.claim.runDatabaseId,
      leaseOwner: input.claim.lease.leaseOwner,
      leaseVersion: input.claim.lease.leaseVersion,
      stateVersion: input.claim.stateVersion,
    },
    data: {
      transcriptId: input.transcriptId,
      transcriptHash: input.transcriptHash,
      stateVersion: { increment: 1 },
    },
  });
  if (update.count !== 1) throw new Error("PIPELINE_ITEM_FENCE_STALE");
}

export function safeTranscriptMetadata(
  transcript: NormalizedTranscript,
): Prisma.InputJsonObject {
  return {
    providerId: transcript.providerId,
    videoId: transcript.videoId,
    language: transcript.language,
    trackKind: transcript.trackKind,
    segmentCount: transcript.segments.length,
    transcriptHash: transcript.transcriptHash,
  };
}
