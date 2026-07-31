import "server-only";

import { Prisma, type PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/db";
import { buildPublicRecommendationEtag } from "../public-etag";
import { normalizePublicBuildRecommendation } from "../public-recommendation-normalize";
import { publicBuildRecommendationSchema } from "../visual-schemas";
import {
  assertAutomationMayProceed,
  lockYoutubeAutomationControl,
} from "./automation-control";
import {
  buildAutomaticRecommendationSnapshot,
  parseAutomaticRecommendationSnapshot,
  type AutomaticRecommendationSnapshot,
} from "./automatic-snapshot";
import { parseCanonicalValidatedAnalysis } from "./canonical-analysis";
import type { YoutubeAutomationFlags } from "./feature-flags";
import {
  actionKey as buildActionKey,
  analysisIdempotencyKey as buildAnalysisIdempotencyKey,
  automationHash,
  publicationKey as buildPublicationKey,
} from "./idempotency";
import {
  acquirePipelineLease,
  releasePipelineLease,
  type PipelineLease,
} from "./lease-store";
import {
  assertPipelineItemClaim,
  type ItemLeaseClaim,
} from "./pipeline-item-lease";
import {
  automaticPublicationQualitySchema,
  evaluateAutomaticPublicationGate,
  type AutomaticPublicationQuality,
} from "./publication-gate";
import {
  YOUTUBE_AUTOMATION_POLICY,
  YOUTUBE_AUTOMATION_POLICY_HASH,
} from "./quality-policy";
import { TRANSCRIPT_ANALYSIS_SCHEMA_VERSION } from "./analysis-schema";

export const AUTOMATIC_PUBLISH_FAILURE_STAGES = [
  "control_locked",
  "item_fenced",
  "source_recalculated",
  "validation_rechecked",
  "analysis_persisted",
  "draft_created",
  "snapshot_written",
  "contribution_created",
  "revision_created",
  "etag_written",
  "audit_created",
  "status_updated",
  "finalized",
] as const;

export type AutomaticPublishFailureStage =
  (typeof AUTOMATIC_PUBLISH_FAILURE_STAGES)[number];

export type AutomaticPublicationResult =
  | {
      published: true;
      recommendationId: string;
      publicationKey: string;
      idempotent: boolean;
    }
  | {
      published: false;
      status:
        | "READY_TO_PUBLISH"
        | "REVIEW_REQUIRED"
        | "BLOCKED"
        | "STOPPED"
        | "CONCURRENT";
      blockCodes: readonly string[];
    };

type TransactionResult = {
  result: AutomaticPublicationResult;
  currentItemAdvanced: boolean;
};

/**
 * No provider or network call is made here. The character lease serializes
 * candidate materialization with publication, while the item claim fences the
 * current worker. Every publication-visible write commits atomically.
 */
export async function publishAutomaticRecommendation(input: {
  pipelineRunId: string;
  itemClaim: ItemLeaseClaim;
  flags: YoutubeAutomationFlags;
  dryRun: boolean;
  now: Date;
  client?: PrismaClient;
  failureInjection?: (stage: AutomaticPublishFailureStage) => void;
  transactionStageHook?: (
    stage: AutomaticPublishFailureStage,
  ) => Promise<void>;
}): Promise<AutomaticPublicationResult> {
  const client = input.client ?? prisma;
  const lockIdentity = await client.guidePipelineItem.findUnique({
    where: { id: input.itemClaim.itemId },
    select: { characterId: true },
  });
  if (!lockIdentity?.characterId) {
    return {
      published: false,
      status: "BLOCKED",
      blockCodes: ["CHARACTER_ID_MISSING"],
    };
  }
  const characterLease = await acquireCharacterPublicationLease({
    characterId: lockIdentity.characterId,
    leaseOwner: `${input.itemClaim.lease.leaseOwner}:publication`,
    now: input.now,
    client,
  });
  if (!characterLease) {
    return {
      published: false,
      status: "CONCURRENT",
      blockCodes: ["CHARACTER_PUBLICATION_LEASE_HELD"],
    };
  }
  try {
    let transactionResult: TransactionResult;
    try {
      transactionResult = await client.$transaction(async (transaction) => {
        const control = await lockYoutubeAutomationControl(transaction);
        await injectStage(input, "control_locked");
        if (control.emergencyStopped) {
          const advanced = await markCurrentItem(transaction, {
            input,
            toStatus: "STOPPED",
            blockCode: "EMERGENCY_STOPPED",
            safeCode: "EMERGENCY_STOPPED",
          });
          return {
            currentItemAdvanced: advanced,
            result: {
              published: false,
              status: "STOPPED",
              blockCodes: ["EMERGENCY_STOPPED"],
            },
          };
        }
        assertAutomationMayProceed(control);
        await assertPipelineItemClaim(
          transaction,
          input.itemClaim,
          input.now,
        );
        await transaction.$queryRaw(Prisma.sql`
          SELECT "id"
          FROM "GuidePipelineItem"
          WHERE "id" = ${input.itemClaim.itemId}
          FOR UPDATE
        `);
        const item = await transaction.guidePipelineItem.findUnique({
          where: { id: input.itemClaim.itemId },
          include: {
            video: { include: { channel: true } },
          },
        });
        const activeRun = await transaction.guidePipelineRun.findUnique({
          where: { id: input.itemClaim.runDatabaseId },
          select: { policyVersion: true, policyHash: true },
        });
        if (
          !item ||
          !activeRun ||
          item.activeRunId !== input.itemClaim.runDatabaseId ||
          item.characterId !== lockIdentity.characterId ||
          item.status !== "READY_TO_PUBLISH" ||
          !item.analysisIdempotencyKey ||
          !item.publicationKey ||
          !item.transcriptId
        ) {
          throw new Error("AUTOMATIC_PUBLISH_PRECONDITION_CHANGED");
        }
        if (
          activeRun.policyVersion !== YOUTUBE_AUTOMATION_POLICY.version ||
          activeRun.policyHash !== YOUTUBE_AUTOMATION_POLICY_HASH
        ) {
          throw new Error("AUTOMATIC_PUBLISH_POLICY_CHANGED");
        }
        await injectStage(input, "item_fenced");

        const sourceVideoIds = await calculateSourceVideoIds(
          transaction,
          item.characterId,
        );
        await injectStage(input, "source_recalculated");
        if (sourceVideoIds.size > 1) {
          await markCharacterReviewRequired(transaction, {
            input,
            characterId: item.characterId,
            sourceCount: sourceVideoIds.size,
          });
          return {
            currentItemAdvanced: true,
            result: {
              published: false,
              status: "REVIEW_REQUIRED",
              blockCodes: ["MULTI_SOURCE_REVIEW_REQUIRED"],
            },
          };
        }

        const canonical = parseCanonicalValidatedAnalysis({
          payload: item.canonicalAnalysisPayload,
          validationHash: item.validationHash,
        });
        const snapshot = parseAutomaticRecommendationSnapshot(
          item.snapshotPayload,
        );
        const storedQuality = automaticPublicationQualitySchema.parse(
          JSON.parse(item.qualityPayload),
        );
        const quality: AutomaticPublicationQuality = {
          ...storedQuality,
          channelAllowed:
            item.video.channel.permissionStatus ===
            "approved_for_processing",
          videoPublic:
            item.video.privacyStatus === "public" &&
            item.video.availabilityStatus === "available",
          transcriptAvailable: Boolean(item.transcriptId),
          schemaValid: true,
          evidenceMatches: true,
        };
        const preview = buildPublicPreview(snapshot, input.now);
        assertPublicationInputs({
          item,
          canonical,
          snapshot,
          quality,
          previewVideoId: preview.videoId,
        });
        await injectStage(input, "validation_rechecked");

        const gate = evaluateAutomaticPublicationGate({
          flags: input.flags,
          dryRun: input.dryRun,
          emergencyStopped: false,
          sourceCount: sourceVideoIds.size,
          quality,
        });
        if (!gate.allowed) {
          if (gate.status === "BLOCKED") {
            const advanced = await markCurrentItem(transaction, {
              input,
              toStatus: "BLOCKED",
              blockCode: gate.blockCodes[0] ?? "PUBLICATION_GATE_BLOCKED",
              safeCode: "PUBLICATION_GATE_BLOCKED",
            });
            return {
              currentItemAdvanced: advanced,
              result: {
                published: false,
                status: "BLOCKED",
                blockCodes: gate.blockCodes,
              },
            };
          }
          return {
            currentItemAdvanced: false,
            result: {
              published: false,
              status: "READY_TO_PUBLISH",
              blockCodes: gate.blockCodes,
            },
          };
        }

        const currentPublished =
          await transaction.characterBuildRecommendation.findFirst({
            where: {
              characterId: snapshot.characterId,
              status: "published",
            },
            orderBy: { publishedAt: "desc" },
            select: {
              id: true,
              publicationKey: true,
              qualityScore: true,
            },
          });
        if (
          currentPublished &&
          currentPublished.publicationKey !== item.publicationKey &&
          currentPublished.qualityScore > quality.overallConfidence
        ) {
          const advanced = await markCurrentItem(transaction, {
            input,
            toStatus: "BLOCKED",
            blockCode: "QUALITY_REGRESSION",
            safeCode: "QUALITY_REGRESSION",
          });
          return {
            currentItemAdvanced: advanced,
            result: {
              published: false,
              status: "BLOCKED",
              blockCodes: ["QUALITY_REGRESSION"],
            },
          };
        }

        const existing =
          await transaction.characterBuildRecommendation.findUnique({
            where: { publicationKey: item.publicationKey },
            select: {
              id: true,
              characterId: true,
              status: true,
              contributions: {
                where: {
                  videoId: item.videoId,
                  usedInPublishedResult: true,
                },
                select: { id: true },
                take: 1,
              },
              revisions: {
                where: { action: "automatic_publish" },
                select: { etag: true },
                take: 1,
              },
            },
          });
        if (existing) {
          if (
            existing.characterId !== item.characterId ||
            existing.status !== "published" ||
            existing.contributions.length !== 1 ||
            !existing.revisions[0]?.etag
          ) {
            throw new Error("AUTOMATIC_PUBLISH_EXISTING_INCOMPLETE");
          }
          const advanced = await markCurrentItem(transaction, {
            input,
            toStatus: "PUBLISHED",
            blockCode: "",
            safeCode: "AUTOMATIC_PUBLISH_IDEMPOTENT",
          });
          return {
            currentItemAdvanced: advanced,
            result: {
              published: true,
              recommendationId: existing.id,
              publicationKey: item.publicationKey,
              idempotent: true,
            },
          };
        }

        const evidenceId = await persistCanonicalAnalysis(transaction, {
          item,
          canonical,
          snapshot,
          now: input.now,
        });
        await injectStage(input, "analysis_persisted");

        const recommendation =
          await transaction.characterBuildRecommendation.create({
            data: {
              characterId: snapshot.characterId,
              status: "pending_review",
              origin: "single_video",
              automationKey: item.analysisIdempotencyKey,
              publicationKey: item.publicationKey,
              verificationMode: "automatic_strict",
              qualityScore: quality.overallConfidence,
              validationPayload: JSON.stringify(
                safeQuality(quality, sourceVideoIds.size),
              ),
            },
            select: { id: true },
          });
        await injectStage(input, "draft_created");
        await transaction.characterBuildRecommendation.update({
          where: { id: recommendation.id },
          data: {
            contextPayload: JSON.stringify(snapshot.contextPayload),
            mainStatsPayload: JSON.stringify(snapshot.mainStatsPayload),
            priorityPayload: JSON.stringify(snapshot.priorityPayload),
            targetsPayload: JSON.stringify(snapshot.targetsPayload),
            structuredPayload: JSON.stringify(snapshot.structuredPayload),
            overallConfidence: snapshot.overallConfidence,
            notes: snapshot.notes,
          },
        });
        await injectStage(input, "snapshot_written");

        await transaction.recommendationVisualContribution.create({
          data: {
            recommendationId: recommendation.id,
            evidenceId,
            videoId: item.videoId,
            startSeconds: snapshot.evidenceStartSeconds,
            endSeconds: snapshot.evidenceEndSeconds,
            exactVisibleText: "",
            contributionRole: "supporting",
            decision: "adopted",
            decisionSummary: "validated_official_transcript",
            usedInPublishedResult: true,
          },
        });
        await injectStage(input, "contribution_created");

        const revision = await transaction.guideRecommendationRevision.create({
          data: {
            recommendationId: recommendation.id,
            action: "automatic_publish",
            actionKey: buildActionKey({
              publicationKey: item.publicationKey,
              action: "automatic-publish-revision",
            }),
            actor: "system:youtube-automation",
            pipelineRunId: input.pipelineRunId,
            publicationKey: item.publicationKey,
            snapshotHash: "",
            etag: "",
            validationPayload: JSON.stringify(
              safeQuality(quality, sourceVideoIds.size),
            ),
            beforePayload: "{}",
            afterPayload: JSON.stringify({
              status: "published",
              publicationKey: item.publicationKey,
            }),
          },
          select: { id: true },
        });
        await injectStage(input, "revision_created");
        await transaction.guideRecommendationRevision.update({
          where: { id: revision.id },
          data: { snapshotHash: preview.etag, etag: preview.etag },
        });
        await injectStage(input, "etag_written");

        await transaction.guideAdminAuditLog.create({
          data: {
            actionKey: buildActionKey({
              publicationKey: item.publicationKey,
              action: "automatic-publish-audit",
            }),
            pipelineRunId: input.pipelineRunId,
            actor: "system:youtube-automation",
            action: "automatic_publish",
            status: "ok",
            detail: JSON.stringify({
              recommendationId: recommendation.id,
              publicationKey: item.publicationKey,
              characterId: snapshot.characterId,
              videoId: item.videoId,
            }),
          },
        });
        await injectStage(input, "audit_created");

        await transaction.characterBuildRecommendation.update({
          where: { id: recommendation.id },
          data: {
            status: "published",
            publishedAt: input.now,
            lastVerifiedAt: input.now,
          },
        });
        await injectStage(input, "status_updated");
        const advanced = await markCurrentItem(transaction, {
          input,
          toStatus: "PUBLISHED",
          blockCode: "",
          safeCode: "AUTOMATIC_SINGLE_SOURCE_PUBLISHED",
          detail: {
            publicationKey: item.publicationKey,
            recommendationId: recommendation.id,
          },
        });
        await injectStage(input, "finalized");
        return {
          currentItemAdvanced: advanced,
          result: {
            published: true,
            recommendationId: recommendation.id,
            publicationKey: item.publicationKey,
            idempotent: false,
          },
        };
      }, {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      });
    } catch (error) {
      if (
        error instanceof Error &&
        error.message === "AUTOMATION_CONTROL_MISSING"
      ) {
        transactionResult = await stopForMissingControl(input, client);
      } else {
        throw error;
      }
    }
    if (transactionResult.currentItemAdvanced) {
      input.itemClaim.stateVersion += 1;
    }
    return transactionResult.result;
  } finally {
    await safelyRelease(characterLease, client);
  }
}

async function acquireCharacterPublicationLease(input: {
  characterId: string;
  leaseOwner: string;
  now: Date;
  client: PrismaClient;
}): Promise<PipelineLease | null> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const lease = await acquirePipelineLease({
      lockKey: `youtube-character-publication:${input.characterId}`,
      leaseOwner: input.leaseOwner,
      now: new Date(input.now.getTime() + attempt),
      ttlMs: 60_000,
      client: input.client,
    });
    if (lease) return lease;
    await new Promise<void>((resolve) => setTimeout(resolve, 20));
  }
  return null;
}

async function calculateSourceVideoIds(
  transaction: Prisma.TransactionClient,
  characterId: string,
): Promise<Set<string>> {
  const [items, contributions] = await Promise.all([
    transaction.guidePipelineItem.findMany({
      where: {
        characterId,
        status: { not: "BLOCKED" },
      },
      select: { videoId: true },
      distinct: ["videoId"],
    }),
    transaction.recommendationVisualContribution.findMany({
      where: {
        recommendation: { characterId, status: "published" },
        usedInPublishedResult: true,
      },
      select: { videoId: true },
      distinct: ["videoId"],
    }),
  ]);
  return new Set(
    [...items, ...contributions].map(({ videoId }) => videoId),
  );
}

async function markCharacterReviewRequired(
  transaction: Prisma.TransactionClient,
  input: {
    input: Parameters<typeof publishAutomaticRecommendation>[0];
    characterId: string;
    sourceCount: number;
  },
): Promise<void> {
  const items = await transaction.guidePipelineItem.findMany({
    where: {
      characterId: input.characterId,
      status: "READY_TO_PUBLISH",
      OR: [
        { leaseOwner: "" },
        {
          id: input.input.itemClaim.itemId,
          leaseOwner: input.input.itemClaim.lease.leaseOwner,
          leaseVersion: input.input.itemClaim.lease.leaseVersion,
          stateVersion: input.input.itemClaim.stateVersion,
        },
      ],
    },
    select: { id: true, stateVersion: true, videoId: true },
  });
  for (const item of items) {
    const update = await transaction.guidePipelineItem.updateMany({
      where: {
        id: item.id,
        status: "READY_TO_PUBLISH",
        stateVersion: item.stateVersion,
      },
      data: {
        status: "REVIEW_REQUIRED",
        blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
        safeErrorCode: "MULTI_SOURCE_REVIEW_REQUIRED",
        stateVersion: { increment: 1 },
      },
    });
    if (update.count !== 1) continue;
    await transaction.guidePipelineEvent.create({
      data: {
        actionKey: automationHash("youtube-multi-source-review-v1", {
          runId: input.input.itemClaim.runDatabaseId,
          itemId: item.id,
          stateVersion: item.stateVersion,
        }),
        runId: input.input.itemClaim.runDatabaseId,
        itemId: item.id,
        fromStatus: "READY_TO_PUBLISH",
        toStatus: "REVIEW_REQUIRED",
        safeCode: "MULTI_SOURCE_REVIEW_REQUIRED",
        detailPayload: JSON.stringify({
          characterId: input.characterId,
          sourceCount: input.sourceCount,
          videoId: item.videoId,
        }),
      },
    });
  }
}

async function markCurrentItem(
  transaction: Prisma.TransactionClient,
  input: {
    input: Parameters<typeof publishAutomaticRecommendation>[0];
    toStatus: "PUBLISHED" | "BLOCKED" | "STOPPED";
    blockCode: string;
    safeCode: string;
    detail?: Record<string, string>;
  },
): Promise<boolean> {
  await assertPipelineItemClaim(
    transaction,
    input.input.itemClaim,
    input.input.now,
  );
  const current = await transaction.guidePipelineItem.findUniqueOrThrow({
    where: { id: input.input.itemClaim.itemId },
    select: { status: true, videoId: true },
  });
  if (current.status === input.toStatus) return false;
  if (current.status !== "READY_TO_PUBLISH") {
    throw new Error("AUTOMATIC_PUBLISH_STATUS_CHANGED");
  }
  const update = await transaction.guidePipelineItem.updateMany({
    where: {
      id: input.input.itemClaim.itemId,
      activeRunId: input.input.itemClaim.runDatabaseId,
      leaseOwner: input.input.itemClaim.lease.leaseOwner,
      leaseVersion: input.input.itemClaim.lease.leaseVersion,
      stateVersion: input.input.itemClaim.stateVersion,
      status: "READY_TO_PUBLISH",
    },
    data: {
      status: input.toStatus,
      blockCode: input.blockCode,
      safeErrorCode: input.safeCode,
      nextRetryAt: null,
      stateVersion: { increment: 1 },
    },
  });
  if (update.count !== 1) throw new Error("PIPELINE_ITEM_FENCE_STALE");
  await transaction.guidePipelineEvent.create({
    data: {
      actionKey: automationHash("youtube-publish-transition-v2", {
        runId: input.input.itemClaim.runDatabaseId,
        itemId: input.input.itemClaim.itemId,
        stateVersion: input.input.itemClaim.stateVersion,
        toStatus: input.toStatus,
      }),
      runId: input.input.itemClaim.runDatabaseId,
      itemId: input.input.itemClaim.itemId,
      fromStatus: "READY_TO_PUBLISH",
      toStatus: input.toStatus,
      safeCode: input.safeCode,
      detailPayload: JSON.stringify({
        videoId: current.videoId,
        ...(input.detail ?? {}),
      }),
    },
  });
  return true;
}

async function stopForMissingControl(
  input: Parameters<typeof publishAutomaticRecommendation>[0],
  client: PrismaClient,
): Promise<TransactionResult> {
  const currentItemAdvanced = await client.$transaction((transaction) =>
    markCurrentItem(transaction, {
      input,
      toStatus: "STOPPED",
      blockCode: "AUTOMATION_CONTROL_MISSING",
      safeCode: "AUTOMATION_CONTROL_MISSING",
    }),
  );
  return {
    currentItemAdvanced,
    result: {
      published: false,
      status: "STOPPED",
      blockCodes: ["AUTOMATION_CONTROL_MISSING"],
    },
  };
}

function assertPublicationInputs(input: {
  item: {
    characterId: string;
    videoId: string;
    metadataHash: string;
    transcriptHash: string;
    analysisIdempotencyKey: string | null;
    publicationKey: string | null;
    analyzerVersion: string;
    promptVersion: string;
    schemaVersion: string;
    policyHash: string;
    video: {
      privacyStatus: string;
      availabilityStatus: string;
      channel: { permissionStatus: string };
    };
  };
  canonical: ReturnType<typeof parseCanonicalValidatedAnalysis>;
  snapshot: AutomaticRecommendationSnapshot;
  quality: AutomaticPublicationQuality;
  previewVideoId: string;
}): void {
  const { item, canonical, quality, snapshot } = input;
  const expectedAnalysisKey = buildAnalysisIdempotencyKey({
    videoId: item.videoId,
    metadataHash: item.metadataHash,
    transcriptHash: item.transcriptHash,
    analyzerVersion: item.analyzerVersion,
    promptVersion: item.promptVersion,
    schemaVersion: item.schemaVersion,
  });
  const expectedPublicationKey = buildPublicationKey({
    characterId: item.characterId,
    analysisKeys: [expectedAnalysisKey],
    policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
    schemaVersion: item.schemaVersion,
  });
  const publishedContentUpdatedAt =
    snapshot.structuredPayload.publishedContentUpdatedAt;
  if (
    typeof publishedContentUpdatedAt !== "string" ||
    Number.isNaN(Date.parse(publishedContentUpdatedAt))
  ) {
    throw new Error("AUTOMATIC_SNAPSHOT_TIMESTAMP_INVALID");
  }
  const expectedSnapshot = buildAutomaticRecommendationSnapshot({
    characterId: canonical.characterId,
    videoId: item.videoId,
    claims: canonical.claims,
    overallConfidence: canonical.overallConfidence,
    publishedContentUpdatedAt: new Date(publishedContentUpdatedAt),
  });
  if (
    item.characterId !== canonical.characterId ||
    item.characterId !== snapshot.characterId ||
    item.videoId !== input.previewVideoId ||
    item.transcriptHash !== canonical.transcriptHash ||
    item.analysisIdempotencyKey !== canonical.analysisIdempotencyKey ||
    item.analysisIdempotencyKey !== expectedAnalysisKey ||
    item.publicationKey !== expectedPublicationKey ||
    item.schemaVersion !== canonical.schemaVersion ||
    item.analyzerVersion !== canonical.providerId ||
    item.promptVersion !== canonical.promptVersion ||
    item.schemaVersion !== TRANSCRIPT_ANALYSIS_SCHEMA_VERSION ||
    item.policyHash !== YOUTUBE_AUTOMATION_POLICY_HASH ||
    snapshot.overallConfidence !== canonical.overallConfidence ||
    automationHash("youtube-automatic-snapshot-v1", snapshot) !==
      automationHash("youtube-automatic-snapshot-v1", expectedSnapshot) ||
    quality.entityCoverage !== canonical.quality.entityCoverage ||
    quality.citationCoverage !== canonical.quality.citationCoverage ||
    quality.timestampCoverage !== canonical.quality.timestampCoverage ||
    quality.minClaimConfidence !== canonical.quality.minClaimConfidence ||
    quality.overallConfidence !== canonical.quality.overallConfidence ||
    quality.channelAllowed !==
      (item.video.channel.permissionStatus === "approved_for_processing") ||
    quality.videoPublic !==
      (item.video.privacyStatus === "public" &&
        item.video.availabilityStatus === "available") ||
    quality.transcriptAvailable !== true ||
    !quality.schemaValid ||
    !quality.evidenceMatches
  ) {
    throw new Error("AUTOMATIC_PUBLISH_INPUT_MISMATCH");
  }
}

async function persistCanonicalAnalysis(
  transaction: Prisma.TransactionClient,
  input: {
    item: {
      videoId: string;
      transcriptId: string | null;
      analysisIdempotencyKey: string | null;
    };
    canonical: ReturnType<typeof parseCanonicalValidatedAnalysis>;
    snapshot: AutomaticRecommendationSnapshot;
    now: Date;
  },
): Promise<string> {
  if (!input.item.transcriptId || !input.item.analysisIdempotencyKey) {
    throw new Error("CANONICAL_ANALYSIS_INPUT_MISSING");
  }
  const safePayload = JSON.stringify(input.canonical);
  const safeEvidencePayload = JSON.stringify({
    claimCount: input.canonical.claims.length,
    evidenceHashes: input.canonical.claims.map((claim) => claim.evidenceHash),
    evidenceSegmentIds: input.canonical.claims.map(
      (claim) => claim.evidenceSegmentIds,
    ),
  });
  const existing = await transaction.guideVisualAnalysisResult.findUnique({
    where: { analysisIdempotencyKey: input.item.analysisIdempotencyKey },
    include: { evidences: { select: { id: true } } },
  });
  if (existing) {
    await transaction.guideVisualAnalysisResult.update({
      where: { id: existing.id },
      data: { rawAiOutput: "", validatedPayload: safePayload },
    });
    await transaction.guideVisualEvidence.updateMany({
      where: { analysisResultId: existing.id },
      data: {
        exactVisibleText: "",
        normalizedPayload: safeEvidencePayload,
      },
    });
    const evidence = existing.evidences[0];
    if (!evidence) throw new Error("ANALYSIS_EVIDENCE_MISSING");
    return evidence.id;
  }
  const result = await transaction.guideVisualAnalysisResult.create({
    data: {
      cacheKey: input.item.analysisIdempotencyKey,
      videoId: input.item.videoId,
      requestHash: input.item.analysisIdempotencyKey,
      providerId: input.canonical.providerId,
      modelIdentifier: input.canonical.modelIdentifier,
      promptVersion: input.canonical.promptVersion,
      schemaVersion: input.canonical.schemaVersion,
      gameDataVersion: "master-current",
      inputKind: "transcript",
      transcriptId: input.item.transcriptId,
      analysisIdempotencyKey: input.item.analysisIdempotencyKey,
      status: "validated",
      rawAiOutput: "",
      validatedPayload: safePayload,
      generatedAt: input.now,
      evidences: {
        create: {
          videoId: input.item.videoId,
          startSeconds: input.snapshot.evidenceStartSeconds,
          endSeconds: input.snapshot.evidenceEndSeconds,
          evidenceType: "transcript_citation",
          normalizedPayload: safeEvidencePayload,
          exactVisibleText: "",
          confidence: input.canonical.overallConfidence,
          validationStatus: "valid",
          approvalStatus: "automatic_strict",
          purposeSummary: "validated_official_transcript",
        },
      },
    },
    include: { evidences: { select: { id: true }, take: 1 } },
  });
  const evidence = result.evidences[0];
  if (!evidence) throw new Error("ANALYSIS_EVIDENCE_MISSING");
  return evidence.id;
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
    throw new Error("AUTOMATIC_SOURCE_VIDEO_MISSING");
  }
  return value;
}

function safeQuality(
  quality: AutomaticPublicationQuality,
  sourceCount: number,
): Record<string, unknown> {
  return {
    sourceCount,
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

async function injectStage(
  input: Parameters<typeof publishAutomaticRecommendation>[0],
  stage: AutomaticPublishFailureStage,
): Promise<void> {
  input.failureInjection?.(stage);
  await input.transactionStageHook?.(stage);
}

async function safelyRelease(
  lease: PipelineLease,
  client: PrismaClient,
): Promise<void> {
  try {
    await releasePipelineLease({ lease, client });
  } catch {
    // Finite leases expire; a cleanup failure must not undo a committed result.
  }
}
