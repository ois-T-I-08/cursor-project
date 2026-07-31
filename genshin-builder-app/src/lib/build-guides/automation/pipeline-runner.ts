import "server-only";

import { prisma } from "@/lib/db";
import type { Prisma } from "@prisma/client";
import {
  TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
  validateTranscriptAnalysis,
} from "./analysis-schema";
import { publishAutomaticRecommendation } from "./auto-publish-store";
import { buildAutomaticRecommendationSnapshot } from "./automatic-snapshot";
import type { DiscoveredGuideCandidate } from "./discovery-service";
import { youtubeAutomationFlags, type YoutubeAutomationFlags } from "./feature-flags";
import {
  analysisIdempotencyKey,
  automationHash,
  publicationKey as buildPublicationKey,
} from "./idempotency";
import { transitionPipelineItem } from "./pipeline-item-store";
import {
  YOUTUBE_AUTOMATION_POLICY,
  YOUTUBE_AUTOMATION_POLICY_HASH,
} from "./quality-policy";
import { normalizeTranscript, chunkTranscript } from "./transcript-normalize";
import {
  fetchPreferredTranscript,
  type TranscriptProvider,
} from "./transcript-provider";
import type { TranscriptAnalysisProvider } from "./transcript-analysis-provider";
import { persistNormalizedTranscript } from "./transcript-store";
import {
  claimProviderCircuitPermission,
  recordProviderFailure,
  recordProviderSuccess,
} from "./circuit-breaker";

export type PipelineRunSummary = Readonly<{
  pipelineRunId: string;
  skipped: boolean;
  dryRun: boolean;
  discovered: number;
  published: number;
  ready: number;
  blocked: number;
  retryable: number;
}>;

export async function runYoutubeGuidePipeline(input: {
  pipelineRunId: string;
  trigger: "schedule" | "workflow_dispatch" | "admin" | "test";
  dryRun: boolean;
  flags?: YoutubeAutomationFlags;
  discover: () => Promise<readonly DiscoveredGuideCandidate[]>;
  transcriptProvider: TranscriptProvider;
  analysisProvider: TranscriptAnalysisProvider;
  loadKnownEntityIds: () => Promise<ReadonlySet<string>>;
  now?: Date;
}): Promise<PipelineRunSummary> {
  const flags = input.flags ?? youtubeAutomationFlags();
  if (
    !flags.enabled ||
    !flags.discoveryEnabled ||
    !flags.transcriptEnabled ||
    !flags.analysisEnabled
  ) {
    return emptySummary(input.pipelineRunId, input.dryRun, true);
  }
  if (
    flags.deepseekAnalysisEnabled &&
    !flags.geminiAnalysisEnabled
  ) {
    // DeepSeek JSON mode is not accepted as a strict-schema automatic path.
    return emptySummary(input.pipelineRunId, input.dryRun, true);
  }
  const now = input.now ?? new Date();
  const runIdempotencyKey = automationHash("youtube-pipeline-run-v1", {
    pipelineRunId: input.pipelineRunId,
    policyHash: YOUTUBE_AUTOMATION_POLICY_HASH,
    dryRun: input.dryRun,
  });
  const run = await prisma.guidePipelineRun.upsert({
    where: { pipelineRunId: input.pipelineRunId },
    create: {
      pipelineRunId: input.pipelineRunId,
      idempotencyKey: runIdempotencyKey,
      trigger: input.trigger,
      mode: input.dryRun ? "dry_run" : "automatic",
      status: "running",
      dryRun: input.dryRun,
      policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
      policyHash: YOUTUBE_AUTOMATION_POLICY_HASH,
      startedAt: now,
    },
    update: {},
  });
  let candidates: readonly DiscoveredGuideCandidate[];
  let knownEntityIds: ReadonlySet<string>;
  try {
    [candidates, knownEntityIds] = await Promise.all([
      input.discover(),
      input.loadKnownEntityIds(),
    ]);
  } catch (error) {
    const errorWithSafeCode = error as { safeCode?: unknown };
    const safeCode =
      typeof errorWithSafeCode.safeCode === "string" &&
      /^[A-Z][A-Z0-9_]{1,63}$/.test(errorWithSafeCode.safeCode)
        ? errorWithSafeCode.safeCode
        : "DISCOVERY_OR_MASTER_FAILED";
    const summary: PipelineRunSummary = {
      ...emptySummary(input.pipelineRunId, input.dryRun, false),
      retryable: 1,
    };
    await prisma.$transaction([
      prisma.guidePipelineRun.update({
        where: { id: run.id },
        data: {
          status: "retryable",
          summaryPayload: JSON.stringify(summary),
          completedAt: new Date(),
        },
      }),
      prisma.guidePipelineEvent.upsert({
        where: {
          actionKey: automationHash("youtube-run-failure-v1", {
            pipelineRunId: input.pipelineRunId,
            safeCode,
          }),
        },
        create: {
          actionKey: automationHash("youtube-run-failure-v1", {
            pipelineRunId: input.pipelineRunId,
            safeCode,
          }),
          runId: run.id,
          toStatus: "RETRYABLE_ERROR",
          safeCode,
          detailPayload: "{}",
        },
        update: {},
      }),
    ]);
    return summary;
  }
  const counts = { published: 0, ready: 0, blocked: 0, retryable: 0 };
  for (const candidate of candidates) {
    const outcome = await processCandidate({
      runDatabaseId: run.id,
      pipelineRunId: input.pipelineRunId,
      candidate,
      transcriptProvider: input.transcriptProvider,
      analysisProvider: input.analysisProvider,
      knownEntityIds,
      flags,
      dryRun: input.dryRun,
      now,
    });
    counts[outcome] += 1;
  }
  const summary: PipelineRunSummary = {
    pipelineRunId: input.pipelineRunId,
    skipped: false,
    dryRun: input.dryRun,
    discovered: candidates.length,
    ...counts,
  };
  await prisma.guidePipelineRun.update({
    where: { id: run.id },
    data: {
      status: counts.retryable > 0 ? "retryable" : "completed",
      summaryPayload: JSON.stringify(summary),
      completedAt: new Date(),
    },
  });
  return summary;
}

async function processCandidate(input: {
  runDatabaseId: string;
  pipelineRunId: string;
  candidate: DiscoveredGuideCandidate;
  transcriptProvider: TranscriptProvider;
  analysisProvider: TranscriptAnalysisProvider;
  knownEntityIds: ReadonlySet<string>;
  flags: YoutubeAutomationFlags;
  dryRun: boolean;
  now: Date;
}): Promise<"published" | "ready" | "blocked" | "retryable"> {
  const existing = await prisma.guidePipelineItem.findUnique({
    where: { discoveryKey: input.candidate.discoveryKey },
  });
  if (existing?.status === "PUBLISHED") return "published";
  if (existing?.status === "BLOCKED") return "blocked";
  const item =
    existing ??
    (await prisma.guidePipelineItem.create({
      data: {
        runId: input.runDatabaseId,
        videoId: input.candidate.video.videoId,
        discoveryKey: input.candidate.discoveryKey,
        status: "DISCOVERED",
        metadataHash: input.candidate.video.metadataHash,
        maxAttempts: YOUTUBE_AUTOMATION_POLICY.maxAttempts.analyzer,
      },
    }));
  if (item.status === "RETRYABLE_ERROR") {
    if (item.attempts >= item.maxAttempts) {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "BLOCKED",
        safeCode: "RETRY_LIMIT_REACHED",
        blockCode: "BLOCKED_RETRY_EXHAUSTED",
      });
      return "blocked";
    }
    if (item.nextRetryAt && item.nextRetryAt.getTime() > input.now.getTime()) {
      return "retryable";
    }
    await transitionPipelineItem({
      itemId: item.id,
      toStatus: "METADATA_FETCHED",
      safeCode: "PIPELINE_RESUMED",
    });
  } else if (
    item.status !== "DISCOVERED" &&
    item.status !== "METADATA_FETCHED"
  ) {
    // An interrupted in-flight stage is left visible for the next recovery
    // sweep; never skip validation or jump directly to publication.
    return "retryable";
  }
  try {
    if (item.status === "DISCOVERED") {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "METADATA_FETCHED",
        safeCode: "METADATA_VALIDATED",
      });
    }
    const transcriptCircuit = await claimProviderCircuitPermission({
      providerId: input.transcriptProvider.providerId,
      now: input.now,
    });
    if (!transcriptCircuit.allowed) {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "RETRYABLE_ERROR",
        safeCode: "PROVIDER_CIRCUIT_OPEN",
        resumeStatus: "METADATA_FETCHED",
        nextRetryAt: transcriptCircuit.retryAt,
      });
      return "retryable";
    }
    const transcriptOutcome = await fetchPreferredTranscript(
      input.transcriptProvider,
      input.candidate.video.videoId,
      [input.candidate.video.language || "ja", "ja", "en"],
    );
    if (!transcriptOutcome.ok) {
      await recordProviderFailure({
        providerId: input.transcriptProvider.providerId,
        safeErrorCode: transcriptOutcome.error.safeCode,
        opensCircuit: transcriptOutcome.error.opensCircuit,
        now: input.now,
      });
      if (transcriptOutcome.error.retryable) {
        await transitionPipelineItem({
          itemId: item.id,
          toStatus: "RETRYABLE_ERROR",
          safeCode: transcriptOutcome.error.safeCode,
          resumeStatus: "METADATA_FETCHED",
          nextRetryAt: new Date(
            input.now.getTime() +
              YOUTUBE_AUTOMATION_POLICY.retryBaseSeconds * 1_000,
          ),
        });
        return "retryable";
      }
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "BLOCKED",
        safeCode: transcriptOutcome.error.safeCode,
        blockCode: transcriptOutcome.blockCode,
      });
      return "blocked";
    }
    await recordProviderSuccess({
      providerId: input.transcriptProvider.providerId,
      now: input.now,
    });
    const transcript = normalizeTranscript(transcriptOutcome.document);
    const stored = await persistNormalizedTranscript({
      transcript,
      now: input.now,
    });
    if (!stored.stored) {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "BLOCKED",
        blockCode: stored.blockCode,
      });
      return "blocked";
    }
    await prisma.guidePipelineItem.update({
      where: { id: item.id },
      data: { transcriptHash: transcript.transcriptHash },
    });
    await transitionPipelineItem({
      itemId: item.id,
      toStatus: "TRANSCRIPT_FETCHED",
      safeCode: "TRANSCRIPT_STORED",
      safeDetail: {
        language: transcript.language,
        segmentCount: transcript.segments.length,
        provider: transcript.providerId,
        transcriptHash: transcript.transcriptHash,
      },
    });
    await transitionPipelineItem({
      itemId: item.id,
      toStatus: "ANALYZING",
      safeCode: "ANALYSIS_STARTED",
    });
    const analyzerVersion = input.analysisProvider.providerId;
    const promptVersion = "youtube-transcript-claims-v1";
    const analysisKey = analysisIdempotencyKey({
      videoId: input.candidate.video.videoId,
      metadataHash: input.candidate.video.metadataHash,
      transcriptHash: transcript.transcriptHash,
      analyzerVersion,
      promptVersion,
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
    });
    const analysisCircuit = await claimProviderCircuitPermission({
      providerId: input.analysisProvider.providerId,
      now: input.now,
    });
    if (!analysisCircuit.allowed) {
      throw Object.assign(new Error("PROVIDER_CIRCUIT_OPEN"), {
        safeCode: "PROVIDER_CIRCUIT_OPEN",
      });
    }
    let completion;
    try {
      completion = await input.analysisProvider.analyze({
        videoId: input.candidate.video.videoId,
        characterId: input.candidate.characterId,
        language: transcript.language,
        chunks: chunkTranscript(transcript),
        allowedEntityIds: [...input.knownEntityIds].sort(),
      });
      await recordProviderSuccess({
        providerId: input.analysisProvider.providerId,
        now: input.now,
      });
    } catch (error) {
      const providerError = error as {
        safeCode?: unknown;
        opensCircuit?: unknown;
      };
      await recordProviderFailure({
        providerId: input.analysisProvider.providerId,
        safeErrorCode:
          typeof providerError.safeCode === "string"
            ? providerError.safeCode
            : "PROVIDER_FAILURE",
        opensCircuit: providerError.opensCircuit === true,
        now: input.now,
      });
      throw error;
    }
    await transitionPipelineItem({
      itemId: item.id,
      toStatus: "VALIDATING",
      safeCode: "ANALYSIS_COMPLETED",
    });
    const validation = validateTranscriptAnalysis(completion.value, {
      expectedCharacterId: input.candidate.characterId,
      knownEntityIds: input.knownEntityIds,
      transcript,
    });
    if (!validation.ok) {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "BLOCKED",
        blockCode: validation.blockCode,
      });
      return "blocked";
    }
    const analysisResult = await persistValidatedAnalysis({
      analysisKey,
      transcriptId: stored.transcriptId,
      videoId: input.candidate.video.videoId,
      providerId: input.analysisProvider.providerId,
      modelIdentifier: completion.modelIdentifier,
      promptVersion,
      validation,
      now: input.now,
    });
    const publicationKey = buildPublicationKey({
      characterId: input.candidate.characterId,
      analysisKeys: [analysisKey],
      policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
    });
    await prisma.guidePipelineItem.update({
      where: { id: item.id },
      data: {
        analysisIdempotencyKey: analysisKey,
        publicationKey,
        analyzerVersion,
        promptVersion,
        schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
        qualityPayload: JSON.stringify(validation.quality),
      },
    });
    await transitionPipelineItem({
      itemId: item.id,
      toStatus: "READY_TO_PUBLISH",
      safeCode: "STRICT_VALIDATION_PASSED",
    });
    const snapshot = buildAutomaticRecommendationSnapshot({
      characterId: input.candidate.characterId,
      videoId: input.candidate.video.videoId,
      claims: validation.claims,
      overallConfidence: validation.analysis.overallConfidence,
      publishedContentUpdatedAt: input.now,
    });
    const publication = await publishAutomaticRecommendation({
      pipelineRunId: input.pipelineRunId,
      pipelineItemId: item.id,
      publicationKey,
      analysisIdempotencyKey: analysisKey,
      evidenceId: analysisResult.evidenceId,
      snapshot,
      quality: {
        sourceCount: 1,
        channelAllowed: true,
        videoPublic: input.candidate.video.privacyStatus === "public",
        transcriptAvailable: true,
        schemaValid: true,
        entityCoverage: validation.quality.entityCoverage,
        citationCoverage: validation.quality.citationCoverage,
        timestampCoverage: validation.quality.timestampCoverage,
        evidenceMatches: true,
        minClaimConfidence: validation.quality.minClaimConfidence,
        overallConfidence: validation.quality.overallConfidence,
        conflicts: [],
      },
      flags: input.flags,
      dryRun: input.dryRun,
      now: input.now,
      leaseOwner: `${input.pipelineRunId}:${item.id}`,
    });
    return publication.published ? "published" : "ready";
  } catch (error) {
    const errorWithSafeCode = error as { safeCode?: unknown };
    const safeCode =
      typeof errorWithSafeCode.safeCode === "string" &&
      /^[A-Z][A-Z0-9_]{1,63}$/.test(errorWithSafeCode.safeCode)
        ? errorWithSafeCode.safeCode
        : error instanceof Error &&
      /^[A-Z][A-Z0-9_]{1,63}$/.test(error.message)
        ? error.message
        : "PIPELINE_ITEM_FAILED";
    const current = await prisma.guidePipelineItem.findUnique({
      where: { id: item.id },
      select: { status: true },
    });
    if (
      current &&
      !["PUBLISHED", "BLOCKED", "RETRYABLE_ERROR"].includes(current.status)
    ) {
      await transitionPipelineItem({
        itemId: item.id,
        toStatus: "RETRYABLE_ERROR",
        safeCode,
        resumeStatus: "METADATA_FETCHED",
        nextRetryAt: new Date(
          input.now.getTime() +
            YOUTUBE_AUTOMATION_POLICY.retryBaseSeconds * 1_000,
        ),
      });
    }
    return "retryable";
  }
}

async function persistValidatedAnalysis(input: {
  analysisKey: string;
  transcriptId: string;
  videoId: string;
  providerId: string;
  modelIdentifier: string;
  promptVersion: string;
  validation: Extract<
    ReturnType<typeof validateTranscriptAnalysis>,
    { ok: true }
  >;
  now: Date;
}): Promise<{ resultId: string; evidenceId: string }> {
  const existing = await prisma.guideVisualAnalysisResult.findUnique({
    where: { analysisIdempotencyKey: input.analysisKey },
    include: { evidences: { select: { id: true }, take: 1 } },
  });
  if (existing?.evidences[0]) {
    return { resultId: existing.id, evidenceId: existing.evidences[0].id };
  }
  const startSeconds = Math.min(
    ...input.validation.claims.map((claim) => claim.startSeconds),
  );
  const endSeconds = Math.max(
    ...input.validation.claims.map((claim) => claim.endSeconds),
  );
  const payload: Prisma.InputJsonObject = {
    analysis: input.validation.analysis as unknown as Prisma.InputJsonObject,
    claims: input.validation.claims as unknown as Prisma.InputJsonArray,
    quality: input.validation.quality,
  };
  const result = await prisma.guideVisualAnalysisResult.create({
    data: {
      cacheKey: input.analysisKey,
      videoId: input.videoId,
      requestHash: input.analysisKey,
      providerId: input.providerId,
      modelIdentifier: input.modelIdentifier,
      promptVersion: input.promptVersion,
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
      gameDataVersion: "master-current",
      inputKind: "transcript",
      transcriptId: input.transcriptId,
      analysisIdempotencyKey: input.analysisKey,
      status: "validated",
      rawAiOutput: "",
      validatedPayload: JSON.stringify(payload),
      generatedAt: input.now,
      evidences: {
        create: {
          videoId: input.videoId,
          startSeconds,
          endSeconds,
          evidenceType: "transcript_citation",
          normalizedPayload: JSON.stringify({
            claimCount: input.validation.claims.length,
          }),
          exactVisibleText: "",
          confidence: input.validation.quality.overallConfidence,
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
  return { resultId: result.id, evidenceId: evidence.id };
}

function emptySummary(
  pipelineRunId: string,
  dryRun: boolean,
  skipped: boolean,
): PipelineRunSummary {
  return {
    pipelineRunId,
    skipped,
    dryRun,
    discovered: 0,
    published: 0,
    ready: 0,
    blocked: 0,
    retryable: 0,
  };
}
