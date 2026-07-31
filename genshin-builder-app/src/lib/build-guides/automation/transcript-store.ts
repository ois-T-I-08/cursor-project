import "server-only";

import type { Prisma, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { transcriptIdentityKey } from "./idempotency";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";
import type { NormalizedTranscript } from "./transcript-normalize";

type TranscriptStoreClient = Pick<
  PrismaClient,
  "$transaction" | "guideTranscript"
>;

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
  client?: TranscriptStoreClient;
}): Promise<TranscriptPersistenceResult> {
  const client = input.client ?? prisma;
  const { transcript } = input;
  const existingByHash = await client.guideTranscript.findUnique({
    where: { transcriptHash: transcript.transcriptHash },
    select: { id: true, videoId: true },
  });
  if (existingByHash) {
    return existingByHash.videoId === transcript.videoId
      ? {
          stored: true,
          transcriptId: existingByHash.id,
          duplicate: true,
        }
      : {
          stored: false,
          blockCode: "BLOCKED_DUPLICATE_TRANSCRIPT_CONTENT",
          existingTranscriptId: existingByHash.id,
        };
  }
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
  return client.$transaction(async (transaction) => {
    const existing = await transaction.guideTranscript.findUnique({
      where: { identityKey },
      select: { id: true },
    });
    if (existing) {
      return { stored: true, transcriptId: existing.id, duplicate: true };
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
    return { stored: true, transcriptId: created.id, duplicate: false };
  });
}

/**
 * Deletes only expired transcript rows; segments cascade and analysis results
 * retain their validated payload while the transcript relation becomes null.
 */
export async function deleteExpiredTranscripts(input: {
  now: Date;
  limit?: number;
  client?: TranscriptStoreClient;
}): Promise<number> {
  const client = input.client ?? prisma;
  const limit = Math.max(1, Math.min(1_000, Math.trunc(input.limit ?? 100)));
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
    if (expired.length === 0) return 0;
    const result = await transaction.guideTranscript.deleteMany({
      where: { id: { in: expired.map(({ id }) => id) } },
    });
    return result.count;
  });
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
