import "server-only";

import type { PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { buildPublicRecommendationEtag } from "../public-etag";
import { normalizePublicBuildRecommendation } from "../public-recommendation-normalize";
import { publicBuildRecommendationSchema } from "../visual-schemas";
import type { AutomaticRecommendationSnapshot } from "./automatic-snapshot";
import type { YoutubeAutomationFlags } from "./feature-flags";
import { actionKey as buildActionKey } from "./idempotency";
import {
  acquirePipelineLease,
  releasePipelineLease,
  type PipelineLease,
} from "./lease-store";
import {
  evaluateAutomaticPublicationGate,
  type AutomaticPublicationQuality,
} from "./publication-gate";

export type AutomaticPublicationResult =
  | {
      published: true;
      recommendationId: string;
      publicationKey: string;
      idempotent: boolean;
    }
  | {
      published: false;
      status: "READY_TO_PUBLISH" | "BLOCKED" | "CONCURRENT";
      blockCodes: readonly string[];
    };

export async function publishAutomaticRecommendation(input: {
  pipelineRunId: string;
  pipelineItemId: string;
  publicationKey: string;
  analysisIdempotencyKey: string;
  evidenceId: string;
  snapshot: AutomaticRecommendationSnapshot;
  quality: AutomaticPublicationQuality;
  flags: YoutubeAutomationFlags;
  dryRun: boolean;
  now: Date;
  leaseOwner: string;
  client?: PrismaClient;
}): Promise<AutomaticPublicationResult> {
  const client = input.client ?? prisma;
  const control = await client.guideAutomationControl.findUnique({
    where: { id: "youtube-guide" },
    select: { emergencyStopped: true },
  });
  const gate = evaluateAutomaticPublicationGate({
    flags: input.flags,
    dryRun: input.dryRun,
    emergencyStopped: control?.emergencyStopped ?? false,
    quality: input.quality,
  });
  if (!gate.allowed) {
    return {
      published: false,
      status: gate.status,
      blockCodes: gate.blockCodes,
    };
  }
  const currentPublished =
    await client.characterBuildRecommendation.findFirst({
      where: {
        characterId: input.snapshot.characterId,
        status: "published",
      },
      orderBy: { publishedAt: "desc" },
      select: { publicationKey: true, qualityScore: true },
    });
  if (
    currentPublished &&
    currentPublished.publicationKey !== input.publicationKey &&
    currentPublished.qualityScore > input.quality.overallConfidence
  ) {
    return {
      published: false,
      status: "BLOCKED",
      blockCodes: ["QUALITY_REGRESSION"],
    };
  }

  // Build and schema-check the complete public DTO before any write.
  const preview = buildPublicPreview(input.snapshot, input.now);
  const lease = await acquirePipelineLease({
    lockKey: `youtube-publication:${input.publicationKey}`,
    leaseOwner: input.leaseOwner,
    now: input.now,
    ttlMs: 60_000,
    client,
  });
  if (!lease) {
    return {
      published: false,
      status: "CONCURRENT",
      blockCodes: ["PUBLICATION_LEASE_HELD"],
    };
  }
  try {
    return await client.$transaction(async (transaction) => {
      const existing =
        await transaction.characterBuildRecommendation.findUnique({
          where: { publicationKey: input.publicationKey },
          select: { id: true },
        });
      if (existing) {
        return {
          published: true as const,
          recommendationId: existing.id,
          publicationKey: input.publicationKey,
          idempotent: true,
        };
      }
      const item = await transaction.guidePipelineItem.findUnique({
        where: { id: input.pipelineItemId },
        include: {
          video: { include: { channel: true } },
          run: { select: { pipelineRunId: true } },
        },
      });
      if (
        !item ||
        item.run.pipelineRunId !== input.pipelineRunId ||
        item.status !== "READY_TO_PUBLISH" ||
        item.video.videoId !== preview.videoId ||
        item.video.privacyStatus !== "public" ||
        item.video.availabilityStatus !== "available" ||
        item.video.channel.permissionStatus !== "approved_for_processing"
      ) {
        throw new Error("automaticPublishPreconditionChanged");
      }
      const evidence = await transaction.guideVisualEvidence.findFirst({
        where: {
          id: input.evidenceId,
          videoId: item.videoId,
          validationStatus: "valid",
        },
        select: { id: true },
      });
      if (!evidence) throw new Error("automaticPublishEvidenceInvalid");

      const recommendation =
        await transaction.characterBuildRecommendation.create({
          data: {
            characterId: input.snapshot.characterId,
            status: "published",
            origin: "single_video",
            contextPayload: JSON.stringify(input.snapshot.contextPayload),
            mainStatsPayload: JSON.stringify(input.snapshot.mainStatsPayload),
            priorityPayload: JSON.stringify(input.snapshot.priorityPayload),
            targetsPayload: JSON.stringify(input.snapshot.targetsPayload),
            structuredPayload: JSON.stringify(input.snapshot.structuredPayload),
            overallConfidence: input.snapshot.overallConfidence,
            notes: input.snapshot.notes,
            automationKey: input.analysisIdempotencyKey,
            publicationKey: input.publicationKey,
            verificationMode: "automatic_strict",
            qualityScore: input.quality.overallConfidence,
            validationPayload: JSON.stringify(safeQuality(input.quality)),
            publishedAt: input.now,
            lastVerifiedAt: input.now,
          },
          select: { id: true },
        });
      await transaction.recommendationVisualContribution.create({
        data: {
          recommendationId: recommendation.id,
          evidenceId: input.evidenceId,
          videoId: item.videoId,
          startSeconds: input.snapshot.evidenceStartSeconds,
          endSeconds: input.snapshot.evidenceEndSeconds,
          // Transcript text must never be copied to the public contribution.
          exactVisibleText: "",
          contributionRole: "supporting",
          decision: "adopted",
          decisionSummary: "validated_official_transcript",
          usedInPublishedResult: true,
        },
      });
      await transaction.guideRecommendationRevision.create({
        data: {
          recommendationId: recommendation.id,
          action: "automatic_publish",
          actionKey: buildActionKey({
            publicationKey: input.publicationKey,
            action: "automatic-publish-revision",
          }),
          actor: "system:youtube-automation",
          pipelineRunId: input.pipelineRunId,
          publicationKey: input.publicationKey,
          snapshotHash: preview.etag,
          etag: preview.etag,
          validationPayload: JSON.stringify(safeQuality(input.quality)),
          beforePayload: "{}",
          afterPayload: JSON.stringify({
            status: "published",
            publicationKey: input.publicationKey,
          }),
        },
      });
      const updated = await transaction.guidePipelineItem.updateMany({
        where: {
          id: item.id,
          status: "READY_TO_PUBLISH",
          publicationKey: input.publicationKey,
          analysisIdempotencyKey: input.analysisIdempotencyKey,
        },
        data: { status: "PUBLISHED", blockCode: "", safeErrorCode: "" },
      });
      if (updated.count !== 1) throw new Error("automaticPublishItemConflict");
      await transaction.guidePipelineEvent.create({
        data: {
          actionKey: buildActionKey({
            publicationKey: input.publicationKey,
            action: "automatic-publish-event",
          }),
          runId: item.runId,
          itemId: item.id,
          fromStatus: "READY_TO_PUBLISH",
          toStatus: "PUBLISHED",
          safeCode: "AUTOMATIC_SINGLE_SOURCE_PUBLISHED",
          detailPayload: JSON.stringify({
            publicationKey: input.publicationKey,
            recommendationId: recommendation.id,
          }),
        },
      });
      await transaction.guideAdminAuditLog.create({
        data: {
          actionKey: buildActionKey({
            publicationKey: input.publicationKey,
            action: "automatic-publish-audit",
          }),
          pipelineRunId: input.pipelineRunId,
          actor: "system:youtube-automation",
          action: "automatic_publish",
          status: "ok",
          detail: JSON.stringify({
            recommendationId: recommendation.id,
            publicationKey: input.publicationKey,
            characterId: input.snapshot.characterId,
            videoId: item.videoId,
          }),
        },
      });
      return {
        published: true as const,
        recommendationId: recommendation.id,
        publicationKey: input.publicationKey,
        idempotent: false,
      };
    });
  } finally {
    await safelyRelease(lease, client);
  }
}

function buildPublicPreview(
  snapshot: AutomaticRecommendationSnapshot,
  now: Date,
): { etag: string; videoId: string } {
  const videoId = extractVideoId(snapshot.structuredPayload);
  const { data } = normalizePublicBuildRecommendation({
    characterId: snapshot.characterId,
    origin: "single_video",
    overallConfidence: snapshot.overallConfidence,
    context: snapshot.contextPayload,
    mainStats: snapshot.mainStatsPayload,
    substatPriority: snapshot.priorityPayload,
    targets: snapshot.targetsPayload,
    structured: snapshot.structuredPayload,
    weapons: snapshot.structuredPayload.weapons,
    artifactRecommendations:
      snapshot.structuredPayload.artifactRecommendations,
    investmentPriority: snapshot.structuredPayload.investmentPriority,
    recommendedStats: snapshot.structuredPayload.recommendedStats,
    caveats: [snapshot.notes],
    lastVerifiedAt: now.toISOString(),
    publishedAt: now.toISOString(),
    updatedAt: now.toISOString(),
    sources: [
      {
        id: `source-${videoId}`,
        videoId,
        title: "validated YouTube guide",
        channelTitle: "approved channel",
        sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
        reviewedAt: now.toISOString(),
      },
    ],
    evidence: [
      {
        fieldPath: "transcript",
        exactVisibleText: "",
        startSeconds: snapshot.evidenceStartSeconds,
        endSeconds: snapshot.evidenceEndSeconds,
        videoId,
      },
    ],
  });
  const parsed = publicBuildRecommendationSchema.parse(data);
  return {
    etag: buildPublicRecommendationEtag(snapshot.characterId, parsed),
    videoId,
  };
}

function extractVideoId(
  structured: AutomaticRecommendationSnapshot["structuredPayload"],
): string {
  const value = structured.automationSourceVideoId;
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{6,20}$/.test(value)) {
    throw new Error("automaticSourceVideoMissing");
  }
  return value;
}

function safeQuality(
  quality: AutomaticPublicationQuality,
): Record<string, unknown> {
  return {
    sourceCount: quality.sourceCount,
    channelAllowed: quality.channelAllowed,
    videoPublic: quality.videoPublic,
    transcriptAvailable: quality.transcriptAvailable,
    schemaValid: quality.schemaValid,
    entityCoverage: quality.entityCoverage,
    citationCoverage: quality.citationCoverage,
    timestampCoverage: quality.timestampCoverage,
    evidenceMatches: quality.evidenceMatches,
    minClaimConfidence: quality.minClaimConfidence,
    overallConfidence: quality.overallConfidence,
    conflictCount: quality.conflicts.length,
  };
}

async function safelyRelease(
  lease: PipelineLease,
  client: PrismaClient,
): Promise<void> {
  try {
    await releasePipelineLease({ lease, client });
  } catch {
    // A finite lease expires. Cleanup failure must not corrupt or undo a
    // committed publication, and no provider content is logged here.
  }
}
