import "server-only";

import { prisma } from "@/lib/db";
import {
  TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
  validateTranscriptAnalysis,
} from "./analysis-schema";
import { readYoutubeAutomationControl } from "./automation-control";
import { publishAutomaticRecommendation } from "./auto-publish-store";
import { buildAutomaticRecommendationSnapshot } from "./automatic-snapshot";
import { canonicalizeValidatedAnalysis } from "./canonical-analysis";
import {
  claimProviderCircuitPermission,
  recordProviderFailure,
  recordProviderSuccess,
} from "./circuit-breaker";
import type { DiscoveredGuideCandidate } from "./discovery-service";
import {
  youtubeAutomationFlags,
  type YoutubeAutomationFlags,
} from "./feature-flags";
import {
  analysisIdempotencyKey,
  automationHash,
  publicationKey as buildPublicationKey,
} from "./idempotency";
import {
  acquirePipelineLease,
  releasePipelineLease,
} from "./lease-store";
import {
  buildPipelineRunSummary,
  parsePipelineRunSummary,
  serializePipelineRunSummary,
  type PipelineRunSummary,
} from "./pipeline-summary";
import {
  claimPipelineItem,
  releasePipelineItemClaim,
  renewPipelineItemClaim,
  updatePipelineItemWithClaim,
  type ItemLeaseClaim,
} from "./pipeline-item-lease";
import { transitionPipelineItem } from "./pipeline-item-store";
import type { SafeProviderError } from "./provider-error";
import {
  YOUTUBE_AUTOMATION_POLICY,
  YOUTUBE_AUTOMATION_POLICY_HASH,
} from "./quality-policy";
import type { TranscriptAnalysisProvider } from "./transcript-analysis-provider";
import {
  chunkTranscript,
  type NormalizedTranscript,
  normalizeTranscript,
} from "./transcript-normalize";
import {
  fetchPreferredTranscript,
  type TranscriptProvider,
} from "./transcript-provider";
import { persistNormalizedTranscript } from "./transcript-store";

export type { PipelineRunSummary } from "./pipeline-summary";

type PipelineItemOutcome =
  | "published"
  | "ready"
  | "reviewRequired"
  | "blocked"
  | "stopped"
  | "retryable";

export type PipelineTestStage =
  | "before_discovery"
  | "before_transcript"
  | "before_analysis"
  | "before_validation_ready"
  | "before_publish";

class EmergencyStoppedError extends Error {
  constructor() {
    super("EMERGENCY_STOPPED");
    this.name = "EmergencyStoppedError";
  }
}

class ItemLeaseLostError extends Error {
  constructor() {
    super("PIPELINE_ITEM_LEASE_LOST");
    this.name = "ItemLeaseLostError";
  }
}

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
  workerId?: string;
  testStageHook?: (stage: PipelineTestStage) => Promise<void>;
}): Promise<PipelineRunSummary> {
  const flags = input.flags ?? youtubeAutomationFlags();
  if (
    !flags.enabled ||
    !flags.discoveryEnabled ||
    !flags.transcriptEnabled ||
    !flags.analysisEnabled ||
    (flags.deepseekAnalysisEnabled && !flags.geminiAnalysisEnabled)
  ) {
    return emptySummary(input.pipelineRunId, input.dryRun, true);
  }
  const now = stageNow(input.now);
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
  const completed = parseCompletedSummary(run.summaryPayload, {
    status: run.status,
    completedAt: run.completedAt,
  });
  if (completed) return completed;

  const entryControl = await readYoutubeAutomationControl();
  if (entryControl.emergencyStopped) {
    const summary = buildPipelineRunSummary({
      ...emptySummary(input.pipelineRunId, input.dryRun, true),
      stopped: 1,
    });
    await finishStoppedRun(run.id, input.pipelineRunId, summary, now);
    return summary;
  }

  let candidates: readonly DiscoveredGuideCandidate[];
  let knownEntityIds: ReadonlySet<string>;
  try {
    await input.testStageHook?.("before_discovery");
    await assertRunnerMayProceed();
    [candidates, knownEntityIds] = await Promise.all([
      input.discover(),
      input.loadKnownEntityIds(),
    ]);
  } catch (error) {
    if (error instanceof EmergencyStoppedError) {
      const summary = buildPipelineRunSummary({
        ...emptySummary(input.pipelineRunId, input.dryRun, true),
        stopped: 1,
      });
      await finishStoppedRun(
        run.id,
        input.pipelineRunId,
        summary,
        stageNow(input.now),
      );
      return summary;
    }
    return finishRunDiscoveryFailure({
      runDatabaseId: run.id,
      pipelineRunId: input.pipelineRunId,
      dryRun: input.dryRun,
      error,
    });
  }

  const uniqueCandidates = [
    ...new Map(
      candidates.map((candidate) => [candidate.discoveryKey, candidate]),
    ).values(),
  ];
  const workerId =
    input.workerId ??
    automationHash("youtube-worker-v1", {
      pipelineRunId: input.pipelineRunId,
      startedAt: now.toISOString(),
    }).slice(0, 16);
  const itemIds: string[] = [];
  let materializationFailures = 0;

  // Pass 0: materialize every source before any item can publish. Candidate
  // insertion and character publication use the same lease namespace.
  for (const candidate of uniqueCandidates) {
    const item = await materializeCandidate({
      runDatabaseId: run.id,
      pipelineRunId: input.pipelineRunId,
      candidate,
      now: stageNow(input.now),
    });
    if (item) itemIds.push(item.id);
    else materializationFailures += 1;
  }

  // Pass 1: discovery -> transcript -> analysis -> strict validation -> READY.
  for (const itemId of itemIds) {
    await processCandidatePassOne({
      itemId,
      runDatabaseId: run.id,
      pipelineRunId: input.pipelineRunId,
      workerId,
      candidates: uniqueCandidates,
      transcriptProvider: input.transcriptProvider,
      analysisProvider: input.analysisProvider,
      knownEntityIds,
      now: input.now,
      testStageHook: input.testStageHook,
    });
  }

  // Pass 2: publish only after every candidate in this run reached a safe
  // pass-one state. The transaction independently recalculates all sources.
  for (const itemId of itemIds) {
    const item = await prisma.guidePipelineItem.findUnique({
      where: { id: itemId },
      select: { status: true },
    });
    if (item?.status !== "READY_TO_PUBLISH") continue;
    const claim = await claimPipelineItem({
      itemId,
      runDatabaseId: run.id,
      pipelineRunId: input.pipelineRunId,
      workerId: `${workerId}:publish`,
      now: stageNow(input.now),
    });
    if (!claim) continue;
    try {
      await input.testStageHook?.("before_publish");
      await checkpoint(claim, input.now);
      await publishAutomaticRecommendation({
        pipelineRunId: input.pipelineRunId,
        itemClaim: claim,
        flags,
        dryRun: input.dryRun,
        now: stageNow(input.now),
      });
    } catch (error) {
      if (
        !(error instanceof EmergencyStoppedError) &&
        !(error instanceof ItemLeaseLostError)
      ) {
        await safelyTransitionRetryable(claim, input.now, error);
      }
    } finally {
      await releasePipelineItemClaim({ claim }).catch(() => undefined);
    }
  }

  const outcomes = await loadFinalOutcomes(itemIds);
  const counts = countOutcomes(outcomes);
  counts.retryable += materializationFailures;
  const summary = buildPipelineRunSummary({
    pipelineRunId: input.pipelineRunId,
    skipped: false,
    dryRun: input.dryRun,
    discovered: uniqueCandidates.length,
    ...counts,
  });
  await prisma.guidePipelineRun.update({
    where: { id: run.id },
    data: {
      status:
        counts.stopped > 0
          ? "stopped"
          : counts.retryable > 0
            ? "retryable"
            : "completed",
      summaryPayload: serializePipelineRunSummary(summary),
      completedAt: stageNow(input.now),
    },
  });
  return summary;
}

async function materializeCandidate(input: {
  runDatabaseId: string;
  pipelineRunId: string;
  candidate: DiscoveredGuideCandidate;
  now: Date;
}): Promise<{ id: string } | null> {
  const lockKey = `youtube-character-publication:${input.candidate.characterId}`;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const now = new Date(input.now.getTime() + attempt);
    const lease = await acquirePipelineLease({
      lockKey,
      leaseOwner: `${input.pipelineRunId}:materialize:${input.candidate.video.videoId}`,
      now,
      ttlMs: 60_000,
    });
    if (!lease) {
      await new Promise<void>((resolve) => setTimeout(resolve, 20));
      continue;
    }
    try {
      const existing = await prisma.guidePipelineItem.findUnique({
        where: { discoveryKey: input.candidate.discoveryKey },
        select: { id: true, videoId: true, characterId: true },
      });
      if (existing) {
        if (
          existing.videoId !== input.candidate.video.videoId ||
          (existing.characterId &&
            existing.characterId !== input.candidate.characterId)
        ) {
          return null;
        }
        if (!existing.characterId) {
          await prisma.guidePipelineItem.update({
            where: { id: existing.id },
            data: { characterId: input.candidate.characterId },
          });
        }
        return { id: existing.id };
      }
      return await prisma.guidePipelineItem.create({
        data: {
          runId: input.runDatabaseId,
          activeRunId: "",
          lastRunId: input.runDatabaseId,
          videoId: input.candidate.video.videoId,
          characterId: input.candidate.characterId,
          discoveryKey: input.candidate.discoveryKey,
          status: "DISCOVERED",
          metadataHash: input.candidate.video.metadataHash,
          maxAttempts: YOUTUBE_AUTOMATION_POLICY.maxAttempts.analyzer,
        },
        select: { id: true },
      });
    } finally {
      await releasePipelineLease({ lease }).catch(() => false);
    }
  }
  return null;
}

async function processCandidatePassOne(input: {
  itemId: string;
  runDatabaseId: string;
  pipelineRunId: string;
  workerId: string;
  candidates: readonly DiscoveredGuideCandidate[];
  transcriptProvider: TranscriptProvider;
  analysisProvider: TranscriptAnalysisProvider;
  knownEntityIds: ReadonlySet<string>;
  now?: Date;
  testStageHook?: (stage: PipelineTestStage) => Promise<void>;
}): Promise<void> {
  const initial = await prisma.guidePipelineItem.findUnique({
    where: { id: input.itemId },
  });
  if (!initial) return;
  const candidate = input.candidates.find(
    (value) => value.discoveryKey === initial.discoveryKey,
  );
  if (!candidate) return;
  if (
    initial.status === "RETRYABLE_ERROR" &&
    initial.nextRetryAt &&
    initial.nextRetryAt.getTime() > stageNow(input.now).getTime()
  ) {
    return;
  }
  const currentAnalysis = isCurrentAnalysisVersion(
    initial,
    input.analysisProvider.providerId,
  );
  if (initial.status === "BLOCKED" && (!initial.analyzerVersion || currentAnalysis)) {
    return;
  }

  const claim = await claimPipelineItem({
    itemId: input.itemId,
    runDatabaseId: input.runDatabaseId,
    pipelineRunId: input.pipelineRunId,
    workerId: `${input.workerId}:pass1`,
    now: stageNow(input.now),
  });
  if (!claim) return;
  try {
    await checkpoint(claim, input.now);
    let item = await prisma.guidePipelineItem.findUniqueOrThrow({
      where: { id: input.itemId },
    });
    const claimedAnalysisCurrent = isCurrentAnalysisVersion(
      item,
      input.analysisProvider.providerId,
    );
    if (
      item.status === "BLOCKED" &&
      (!item.analyzerVersion || claimedAnalysisCurrent)
    ) {
      return;
    }
    let fetchedTerminalTranscript: NormalizedTranscript | null = null;
    if (item.status === "PUBLISHED" || item.status === "REVIEW_REQUIRED") {
      await input.testStageHook?.("before_transcript");
      await checkpoint(claim, input.now);
      fetchedTerminalTranscript = await fetchTranscriptForClaim({
        claim,
        candidate,
        transcriptProvider: input.transcriptProvider,
        now: input.now,
      });
      if (!fetchedTerminalTranscript) return;
      if (
        isCurrentAnalysisInput({
          item,
          candidate,
          transcript: fetchedTerminalTranscript,
          analyzerVersion: input.analysisProvider.providerId,
        })
      ) {
        return;
      }
      const transcriptChanged =
        item.transcriptHash !== fetchedTerminalTranscript.transcriptHash;
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "METADATA_FETCHED",
        safeCode: transcriptChanged
          ? "TRANSCRIPT_HASH_CHANGED"
          : "ANALYSIS_INPUT_CHANGED",
        safeDetail: {
          transcriptChanged,
          previousTranscriptHash: item.transcriptHash,
          currentTranscriptHash: fetchedTerminalTranscript.transcriptHash,
        },
      });
      item = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: input.itemId },
      });
    }
    const shouldReanalyze =
      item.status === "BLOCKED" && !claimedAnalysisCurrent;
    if (shouldReanalyze || item.status === "STOPPED") {
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "METADATA_FETCHED",
        safeCode: shouldReanalyze
          ? "ANALYZER_VERSION_CHANGED"
          : "PIPELINE_RESUMED_AFTER_STOP",
      });
      item = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: input.itemId },
      });
    } else if (item.status === "RETRYABLE_ERROR") {
      if (item.attempts >= item.maxAttempts) {
        await transitionPipelineItem({
          claim,
          now: stageNow(input.now),
          toStatus: "BLOCKED",
          safeCode: "RETRY_LIMIT_REACHED",
          blockCode: "BLOCKED_RETRY_EXHAUSTED",
        });
        return;
      }
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "METADATA_FETCHED",
        safeCode: "PIPELINE_RESUMED",
      });
      item = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: input.itemId },
      });
    } else if (item.status === "ANALYZING" || item.status === "VALIDATING") {
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "RETRYABLE_ERROR",
        safeCode: "INTERRUPTED_STAGE_RECOVERED",
        resumeStatus: "METADATA_FETCHED",
        nextRetryAt: null,
      });
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "METADATA_FETCHED",
        safeCode: "PIPELINE_RESUMED",
      });
      item = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: input.itemId },
      });
    }
    if (item.status === "READY_TO_PUBLISH") return;
    if (item.status === "DISCOVERED") {
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "METADATA_FETCHED",
        safeCode: "METADATA_VALIDATED",
      });
      item = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: input.itemId },
      });
    }

    let transcript: NormalizedTranscript;
    let transcriptId: string;
    if (item.status === "TRANSCRIPT_FETCHED" && item.transcriptId) {
      const stored = await loadNormalizedTranscript(item.transcriptId);
      if (!stored) throw new Error("STORED_TRANSCRIPT_MISSING");
      transcript = stored;
      transcriptId = item.transcriptId;
    } else {
      if (!fetchedTerminalTranscript) {
        await input.testStageHook?.("before_transcript");
        await checkpoint(claim, input.now);
      }
      const fetchedTranscript =
        fetchedTerminalTranscript ??
        (await fetchTranscriptForClaim({
          claim,
          candidate,
          transcriptProvider: input.transcriptProvider,
          now: input.now,
        }));
      if (!fetchedTranscript) return;
      transcript = fetchedTranscript;
      const stored = await persistNormalizedTranscript({
        transcript,
        now: stageNow(input.now),
        itemClaim: claim,
      });
      if (!stored.stored) {
        await transitionPipelineItem({
          claim,
          now: stageNow(input.now),
          toStatus: "BLOCKED",
          blockCode: stored.blockCode,
        });
        return;
      }
      transcriptId = stored.transcriptId;
      await updatePipelineItemWithClaim({
        claim,
        now: stageNow(input.now),
        data: {
          metadataHash: candidate.video.metadataHash,
          analysisIdempotencyKey: null,
          publicationKey: null,
          analyzerVersion: "",
          promptVersion: "",
          schemaVersion: "",
          qualityPayload: "{}",
          canonicalAnalysisPayload: "{}",
          validationHash: "",
          snapshotPayload: "{}",
          policyHash: "",
          blockCode: "",
          safeErrorCode: "",
        },
      });
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "TRANSCRIPT_FETCHED",
        safeCode: "TRANSCRIPT_STORED",
        safeDetail: {
          language: transcript.language,
          segmentCount: transcript.segments.length,
          provider: transcript.providerId,
          transcriptHash: transcript.transcriptHash,
        },
      });
    }

    await input.testStageHook?.("before_analysis");
    await checkpoint(claim, input.now);
    await transitionPipelineItem({
      claim,
      now: stageNow(input.now),
      toStatus: "ANALYZING",
      safeCode: "ANALYSIS_STARTED",
    });
    const analyzerVersion = input.analysisProvider.providerId;
    const promptVersion = "youtube-transcript-claims-v1";
    const analysisKey = analysisIdempotencyKey({
      videoId: candidate.video.videoId,
      metadataHash: candidate.video.metadataHash,
      transcriptHash: transcript.transcriptHash,
      analyzerVersion,
      promptVersion,
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
    });
    const analysisCircuit = await claimProviderCircuitPermission({
      providerId: input.analysisProvider.providerId,
      probeOwner: `${claim.lease.leaseOwner}:analysis`,
      now: stageNow(input.now),
    });
    if (!analysisCircuit.allowed) {
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "RETRYABLE_ERROR",
        safeCode: "PROVIDER_CIRCUIT_OPEN",
        resumeStatus: "TRANSCRIPT_FETCHED",
        nextRetryAt: analysisCircuit.retryAt,
      });
      return;
    }
    let completion;
    try {
      completion = await input.analysisProvider.analyze({
        videoId: candidate.video.videoId,
        characterId: candidate.characterId,
        language: transcript.language,
        chunks: chunkTranscript(transcript),
        allowedEntityIds: [...input.knownEntityIds].sort(),
      });
      await checkpoint(claim, input.now);
      assertCircuitResultRecorded(await recordProviderSuccess({
        permit: analysisCircuit.permit,
        now: stageNow(input.now),
      }));
    } catch (error) {
      const providerError = asSafeProviderError(error);
      if (providerError) {
        assertCircuitResultRecorded(await recordProviderFailure({
          permit: analysisCircuit.permit,
          safeErrorCode: providerError.safeCode,
          opensCircuit: providerError.opensCircuit,
          now: stageNow(input.now),
        }));
        if (!providerError.retryable) {
          await transitionPipelineItem({
            claim,
            now: stageNow(input.now),
            toStatus: "BLOCKED",
            safeCode: providerError.safeCode,
            blockCode: blockCodeForProviderError(providerError),
          });
          return;
        }
      }
      throw error;
    }

    await transitionPipelineItem({
      claim,
      now: stageNow(input.now),
      toStatus: "VALIDATING",
      safeCode: "ANALYSIS_COMPLETED",
    });
    await input.testStageHook?.("before_validation_ready");
    await checkpoint(claim, input.now);
    const validation = validateTranscriptAnalysis(completion.value, {
      expectedCharacterId: candidate.characterId,
      knownEntityIds: input.knownEntityIds,
      transcript,
    });
    if (!validation.ok) {
      await transitionPipelineItem({
        claim,
        now: stageNow(input.now),
        toStatus: "BLOCKED",
        blockCode: validation.blockCode,
      });
      return;
    }
    const canonical = canonicalizeValidatedAnalysis({
      validation,
      transcriptHash: transcript.transcriptHash,
      analysisIdempotencyKey: analysisKey,
      providerId: input.analysisProvider.providerId,
      modelIdentifier: completion.modelIdentifier,
      promptVersion,
    });
    const publicationKey = buildPublicationKey({
      characterId: candidate.characterId,
      analysisKeys: [analysisKey],
      policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
    });
    const snapshot = buildAutomaticRecommendationSnapshot({
      characterId: candidate.characterId,
      videoId: candidate.video.videoId,
      claims: canonical.canonical.claims,
      overallConfidence: canonical.canonical.overallConfidence,
      publishedContentUpdatedAt: stageNow(input.now),
    });
    await checkpoint(claim, input.now);
    await updatePipelineItemWithClaim({
      claim,
      now: stageNow(input.now),
      data: {
        characterId: candidate.characterId,
        transcriptId,
        transcriptHash: transcript.transcriptHash,
        analysisIdempotencyKey: analysisKey,
        publicationKey,
        analyzerVersion,
        promptVersion,
        schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
        qualityPayload: JSON.stringify({
          channelAllowed: true,
          videoPublic: candidate.video.privacyStatus === "public",
          transcriptAvailable: true,
          schemaValid: true,
          entityCoverage: validation.quality.entityCoverage,
          citationCoverage: validation.quality.citationCoverage,
          timestampCoverage: validation.quality.timestampCoverage,
          evidenceMatches: true,
          minClaimConfidence: validation.quality.minClaimConfidence,
          overallConfidence: validation.quality.overallConfidence,
          conflicts: [],
        }),
        canonicalAnalysisPayload: canonical.payload,
        validationHash: canonical.validationHash,
        snapshotPayload: JSON.stringify(snapshot),
        policyHash: YOUTUBE_AUTOMATION_POLICY_HASH,
      },
    });
    await transitionPipelineItem({
      claim,
      now: stageNow(input.now),
      toStatus: "READY_TO_PUBLISH",
      safeCode: "STRICT_VALIDATION_PASSED",
    });
  } catch (error) {
    if (
      error instanceof EmergencyStoppedError ||
      error instanceof ItemLeaseLostError ||
      (error instanceof Error &&
        ["PIPELINE_ITEM_LEASE_LOST", "PIPELINE_ITEM_FENCE_STALE"].includes(
          error.message,
        ))
    ) {
      return;
    }
    await safelyTransitionRetryable(claim, input.now, error);
  } finally {
    await releasePipelineItemClaim({ claim }).catch(() => undefined);
  }
}

async function fetchTranscriptForClaim(input: {
  claim: ItemLeaseClaim;
  candidate: DiscoveredGuideCandidate;
  transcriptProvider: TranscriptProvider;
  now?: Date;
}): Promise<NormalizedTranscript | null> {
  const circuit = await claimProviderCircuitPermission({
    providerId: input.transcriptProvider.providerId,
    probeOwner: `${input.claim.lease.leaseOwner}:transcript`,
    now: stageNow(input.now),
  });
  if (!circuit.allowed) {
    await transitionPipelineItem({
      claim: input.claim,
      now: stageNow(input.now),
      toStatus: "RETRYABLE_ERROR",
      safeCode: "PROVIDER_CIRCUIT_OPEN",
      resumeStatus: "METADATA_FETCHED",
      nextRetryAt: circuit.retryAt,
    });
    return null;
  }
  const outcome = await fetchPreferredTranscript(
    input.transcriptProvider,
    input.candidate.video.videoId,
    [input.candidate.video.language || "ja", "ja", "en"],
  );
  await checkpoint(input.claim, input.now);
  if (!outcome.ok) {
    assertCircuitResultRecorded(
      await recordProviderFailure({
        permit: circuit.permit,
        safeErrorCode: outcome.error.safeCode,
        opensCircuit: outcome.error.opensCircuit,
        now: stageNow(input.now),
      }),
    );
    if (outcome.error.retryable) {
      await transitionPipelineItem({
        claim: input.claim,
        now: stageNow(input.now),
        toStatus: "RETRYABLE_ERROR",
        safeCode: outcome.error.safeCode,
        resumeStatus: "METADATA_FETCHED",
        nextRetryAt: retryAt(input.now),
      });
    } else {
      await transitionPipelineItem({
        claim: input.claim,
        now: stageNow(input.now),
        toStatus: "BLOCKED",
        safeCode: outcome.error.safeCode,
        blockCode: outcome.blockCode,
      });
    }
    return null;
  }
  assertCircuitResultRecorded(
    await recordProviderSuccess({
      permit: circuit.permit,
      now: stageNow(input.now),
    }),
  );
  return normalizeTranscript(outcome.document);
}

async function checkpoint(
  claim: ItemLeaseClaim,
  fixedNow?: Date,
): Promise<void> {
  const now = stageNow(fixedNow);
  const renewed = await renewPipelineItemClaim({ claim, now });
  if (!renewed) throw new ItemLeaseLostError();
  const control = await readYoutubeAutomationControl();
  if (!control.emergencyStopped) return;
  const item = await prisma.guidePipelineItem.findUnique({
    where: { id: claim.itemId },
    select: { status: true },
  });
  if (item && item.status !== "STOPPED") {
    await transitionPipelineItem({
      claim,
      now,
      toStatus: "STOPPED",
      safeCode:
        control.reason === "CONTROL_ROW_MISSING"
          ? "AUTOMATION_CONTROL_MISSING"
          : "EMERGENCY_STOPPED",
      blockCode:
        control.reason === "CONTROL_ROW_MISSING"
          ? "AUTOMATION_CONTROL_MISSING"
          : "EMERGENCY_STOPPED",
    });
  }
  throw new EmergencyStoppedError();
}

async function assertRunnerMayProceed(): Promise<void> {
  const control = await readYoutubeAutomationControl();
  if (control.emergencyStopped) throw new EmergencyStoppedError();
}

async function safelyTransitionRetryable(
  claim: ItemLeaseClaim,
  fixedNow: Date | undefined,
  error: unknown,
): Promise<void> {
  const current = await prisma.guidePipelineItem.findUnique({
    where: { id: claim.itemId },
    select: { status: true },
  });
  if (
    !current ||
    [
      "BLOCKED",
      "RETRYABLE_ERROR",
      "STOPPED",
    ].includes(current.status)
  ) {
    return;
  }
  const providerError = asSafeProviderError(error);
  if (providerError && !providerError.retryable) {
    await transitionPipelineItem({
      claim,
      now: stageNow(fixedNow),
      toStatus: "BLOCKED",
      safeCode: providerError.safeCode,
      blockCode: blockCodeForProviderError(providerError),
    }).catch(() => undefined);
    return;
  }
  await transitionPipelineItem({
    claim,
    now: stageNow(fixedNow),
    toStatus: "RETRYABLE_ERROR",
    safeCode: safeCodeOf(error),
    resumeStatus: "METADATA_FETCHED",
    nextRetryAt: retryAt(fixedNow),
  }).catch(() => undefined);
}

async function loadNormalizedTranscript(
  transcriptId: string,
): Promise<NormalizedTranscript | null> {
  const transcript = await prisma.guideTranscript.findUnique({
    where: { id: transcriptId },
    include: { segments: { orderBy: { segmentIndex: "asc" } } },
  });
  if (!transcript) return null;
  return {
    providerId: transcript.providerId,
    videoId: transcript.videoId,
    language: transcript.language,
    trackKind: transcript.trackKind as "manual" | "asr",
    sourceTrackId: transcript.sourceTrackId,
    fetchedAt: transcript.fetchedAt,
    transcriptHash: transcript.transcriptHash,
    segments: transcript.segments.map((segment) => ({
      index: segment.segmentIndex,
      segmentKey: segment.segmentKey,
      startSeconds: segment.startSeconds,
      durationSeconds: segment.durationSeconds,
      text: segment.text,
      textHash: segment.textHash,
    })),
  };
}

async function loadFinalOutcomes(
  itemIds: readonly string[],
): Promise<PipelineItemOutcome[]> {
  if (itemIds.length === 0) return [];
  const items = await prisma.guidePipelineItem.findMany({
    where: { id: { in: [...itemIds] } },
    select: { status: true },
  });
  return items.map(({ status }) => {
    switch (status) {
      case "PUBLISHED":
        return "published";
      case "READY_TO_PUBLISH":
        return "ready";
      case "REVIEW_REQUIRED":
        return "reviewRequired";
      case "BLOCKED":
        return "blocked";
      case "STOPPED":
        return "stopped";
      default:
        return "retryable";
    }
  });
}

function countOutcomes(
  outcomes: readonly PipelineItemOutcome[],
): Record<PipelineItemOutcome, number> {
  const result = {
    published: 0,
    ready: 0,
    reviewRequired: 0,
    blocked: 0,
    stopped: 0,
    retryable: 0,
  };
  for (const outcome of outcomes) result[outcome] += 1;
  return result;
}

function assertCircuitResultRecorded(
  result: "recorded" | "stale",
): asserts result is "recorded" {
  if (result !== "recorded") {
    throw new Error("PROVIDER_CIRCUIT_PERMIT_STALE");
  }
}

async function finishRunDiscoveryFailure(input: {
  runDatabaseId: string;
  pipelineRunId: string;
  dryRun: boolean;
  error: unknown;
}): Promise<PipelineRunSummary> {
  const safeCode = safeCodeOf(input.error, "DISCOVERY_OR_MASTER_FAILED");
  const summary = buildPipelineRunSummary({
    ...emptySummary(input.pipelineRunId, input.dryRun, false),
    retryable: 1,
  });
  const actionKey = automationHash("youtube-run-failure-v1", {
    pipelineRunId: input.pipelineRunId,
    safeCode,
  });
  await prisma.$transaction([
    prisma.guidePipelineRun.update({
      where: { id: input.runDatabaseId },
      data: {
        status: "retryable",
        summaryPayload: serializePipelineRunSummary(summary),
        completedAt: new Date(),
      },
    }),
    prisma.guidePipelineEvent.upsert({
      where: { actionKey },
      create: {
        actionKey,
        runId: input.runDatabaseId,
        toStatus: "RETRYABLE_ERROR",
        safeCode,
        detailPayload: "{}",
      },
      update: {},
    }),
  ]);
  return summary;
}

async function finishStoppedRun(
  runDatabaseId: string,
  pipelineRunId: string,
  summary: PipelineRunSummary,
  now: Date,
): Promise<void> {
  const actionKey = automationHash("youtube-run-stopped-v1", {
    pipelineRunId,
  });
  await prisma.$transaction([
    prisma.guidePipelineRun.update({
      where: { id: runDatabaseId },
      data: {
        status: "stopped",
        summaryPayload: serializePipelineRunSummary(summary),
        completedAt: now,
      },
    }),
    prisma.guidePipelineEvent.upsert({
      where: { actionKey },
      create: {
        actionKey,
        runId: runDatabaseId,
        toStatus: "STOPPED",
        safeCode: "EMERGENCY_STOPPED",
        detailPayload: "{}",
      },
      update: {},
    }),
  ]);
}

function parseCompletedSummary(
  payload: string,
  state: { status: string; completedAt: Date | null },
): PipelineRunSummary | null {
  if (!state.completedAt || state.status !== "completed") return null;
  return parsePipelineRunSummary(payload);
}

function asSafeProviderError(error: unknown): SafeProviderError | null {
  if (
    error instanceof Error &&
    error.name === "SafeProviderError" &&
    "safeCode" in error &&
    typeof error.safeCode === "string" &&
    "retryable" in error &&
    typeof error.retryable === "boolean" &&
    "opensCircuit" in error &&
    typeof error.opensCircuit === "boolean"
  ) {
    return error as SafeProviderError;
  }
  return null;
}

function blockCodeForProviderError(error: SafeProviderError): string {
  switch (error.safeCode) {
    case "AUTH_NOT_CONFIGURED":
    case "AUTH_REJECTED":
      return "BLOCKED_PROVIDER_AUTH";
    case "INVALID_RESPONSE":
    case "RESPONSE_TOO_LARGE":
      return "BLOCKED_INVALID_ANALYSIS";
    case "TRANSCRIPT_UNAVAILABLE":
      return "BLOCKED_TRANSCRIPT_UNAVAILABLE";
    case "NOT_FOUND":
      return "BLOCKED_PROVIDER_REQUEST";
    default:
      return "BLOCKED_PROVIDER_REQUEST";
  }
}

function safeCodeOf(error: unknown, fallback = "PIPELINE_ITEM_FAILED"): string {
  const provider = asSafeProviderError(error);
  if (provider) return provider.safeCode;
  const withCode = error as { safeCode?: unknown };
  if (
    typeof withCode?.safeCode === "string" &&
    /^[A-Z][A-Z0-9_]{1,63}$/.test(withCode.safeCode)
  ) {
    return withCode.safeCode;
  }
  if (
    error instanceof Error &&
    /^[A-Z][A-Z0-9_]{1,63}$/.test(error.message)
  ) {
    return error.message;
  }
  return fallback;
}

function retryAt(fixedNow?: Date): Date {
  return new Date(
    stageNow(fixedNow).getTime() +
      YOUTUBE_AUTOMATION_POLICY.retryBaseSeconds * 1_000,
  );
}

function isCurrentAnalysisVersion(
  item: {
    analyzerVersion: string;
    promptVersion: string;
    schemaVersion: string;
    policyHash: string;
  },
  analyzerVersion: string,
): boolean {
  return (
    item.analyzerVersion === analyzerVersion &&
    item.promptVersion === "youtube-transcript-claims-v1" &&
    item.schemaVersion === TRANSCRIPT_ANALYSIS_SCHEMA_VERSION &&
    item.policyHash === YOUTUBE_AUTOMATION_POLICY_HASH
  );
}

function isCurrentAnalysisInput(input: {
  item: {
    metadataHash: string;
    transcriptHash: string;
    analysisIdempotencyKey: string | null;
    analyzerVersion: string;
    promptVersion: string;
    schemaVersion: string;
    policyHash: string;
  };
  candidate: DiscoveredGuideCandidate;
  transcript: NormalizedTranscript;
  analyzerVersion: string;
}): boolean {
  if (
    !isCurrentAnalysisVersion(input.item, input.analyzerVersion) ||
    input.item.metadataHash !== input.candidate.video.metadataHash ||
    input.item.transcriptHash !== input.transcript.transcriptHash
  ) {
    return false;
  }
  return (
    input.item.analysisIdempotencyKey ===
    analysisIdempotencyKey({
      videoId: input.candidate.video.videoId,
      metadataHash: input.candidate.video.metadataHash,
      transcriptHash: input.transcript.transcriptHash,
      analyzerVersion: input.analyzerVersion,
      promptVersion: "youtube-transcript-claims-v1",
      schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
    })
  );
}

function stageNow(fixedNow?: Date): Date {
  return fixedNow ? new Date(fixedNow) : new Date();
}

function emptySummary(
  pipelineRunId: string,
  dryRun: boolean,
  skipped: boolean,
): PipelineRunSummary {
  return buildPipelineRunSummary({
    pipelineRunId,
    skipped,
    dryRun,
    discovered: 0,
    published: 0,
    ready: 0,
    reviewRequired: 0,
    blocked: 0,
    stopped: 0,
    retryable: 0,
  });
}
