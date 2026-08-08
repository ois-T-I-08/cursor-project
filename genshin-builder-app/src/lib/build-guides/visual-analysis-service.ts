import "server-only";

import { prisma } from "@/lib/db";
import { logSafeFailure } from "@/lib/safe-error-log";
import { buildVisualRequestHash } from "./cache-key";
import { loadCharacterHints, resolveCharacterCandidates } from "./character-match";
import {
  buildUncoveredEligibleQueue,
  getCoverageMetrics,
  type CoverageMetrics,
} from "./visual-coverage";
import {
  AnalysisRangeError,
  normalizeAnalysisRanges,
} from "./analysis-ranges";
import { GeminiError } from "./gemini-settings";
import { GeminiYouTubeVisualAnalysisProvider } from "./gemini-youtube-provider";
import { geminiVideoSettings } from "./gemini-settings";
import type { VideoVisualAnalysisProvider } from "./visual-provider";
import {
  validateVisualAnalysisResult,
  VisualValidationError,
} from "./visual-validator";
import {
  GUIDE_GAME_DATA_VERSION,
  GEMINI_PROVIDER_ID,
  VISUAL_PROMPT_VERSION,
  VISUAL_SCHEMA_VERSION,
} from "./versions";
import { GENSIN_VIDEO_TITLE_MARKER } from "./genshin-video-title";
import {
  assertEmergencyStopAllowsWork,
  evaluateVisualAutoPublishGate,
} from "./automation/safety-gates";
import { autoPublishVisualRecommendations } from "./visual-auto-publish";
import type { VisualAutoPublishResult } from "./visual-auto-publish";
import {
  assertVisualProviderNotCoolingDown,
  assertVisualTokenBudget,
  classifyVisualAnalysisFailure,
  logVisualAnalysisEvent,
  noteVisualProviderCooldown,
  shouldAbortPendingBatch,
  VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS,
} from "./visual-analysis-safety";
import { readGlobalAiEmergencyControl } from "@/lib/ai/global-ai-emergency";
import {
  runVisualPostProcess,
  VisualPostProcessError,
} from "./visual-postprocess";
import {
  buildLongformChunkUsageRecord,
  buildLongformPartialState,
  isLongformPublishable,
  LongformPlanningError,
  needsLongformFullDiscovery,
  planLongformChunks,
  reduceLongformChunkResults,
  type LongformChunkUsageRecord,
  type LongformPlan,
} from "./visual-longform";
import type { VideoVisualAnalysisResult } from "./visual-schemas";

export class GuideVisualAnalysisError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "GuideVisualAnalysisError";
  }
}

const activeJobs = new Set<string>();

/** Idempotency: videoId + analysisStage + config versions (via requestHash). */
const VISUAL_ANALYSIS_STAGE = "visual_full_or_clipped";

export async function analyzeVideoVisuals(input: {
  videoId: string;
  force?: boolean;
  requestedRanges?: Array<{
    startSeconds: number;
    endSeconds: number;
    reason: string;
  }>;
  targetCharacterIds?: string[];
  provider?: VideoVisualAnalysisProvider;
  /**
   * When full_discovery exceeds the 80k hard max, run chunked long-form.
   * Pending/batch callers should pass false to avoid runaway cost.
   */
  allowLongform?: boolean;
  /**
   * Canary / manual override: never auto-publish regardless of gate flags.
   * Production default: omit / false — after success, evaluateVisualAutoPublishGate
   * may auto-approve+publish when env + Emergency allow.
   */
  skipAutoPublish?: boolean;
}): Promise<{
  jobId: string;
  cacheKey: string;
  status: string;
  evidenceCount: number;
  recommendationIds: string[];
  analysisMode: "full_discovery" | "clipped_detail";
  fps: number;
  autoPublish?: VisualAutoPublishResult | null;
}> {
  try {
    await assertEmergencyStopAllowsWork();
  } catch {
    throw new GuideVisualAnalysisError("emergencyStopped");
  }

  try {
    assertVisualProviderNotCoolingDown();
  } catch {
    throw new GuideVisualAnalysisError("geminiProviderCoolingDown");
  }

  const video = await prisma.guideVideo.findUnique({
    where: { videoId: input.videoId },
    include: { channel: true },
  });
  if (!video) throw new GuideVisualAnalysisError("videoNotFound");
  if (!video.channel.enabled) throw new GuideVisualAnalysisError("channelDisabled");
  if (video.channel.permissionStatus !== "approved_for_processing") {
    throw new GuideVisualAnalysisError("permissionNotApproved");
  }
  if (video.privacyStatus !== "public") {
    throw new GuideVisualAnalysisError("videoNotPublic");
  }

  const settings = geminiVideoSettings();
  const clipped =
    input.requestedRanges != null && input.requestedRanges.length > 0;
  let requestedRanges = input.requestedRanges;
  if (clipped) {
    try {
      requestedRanges = normalizeAnalysisRanges({
        ranges: input.requestedRanges!,
        durationSeconds: video.durationSeconds,
        maxRangeSeconds: settings.maxRangeSeconds,
        maxRanges: settings.maxRangesPerRequest,
      });
    } catch (error) {
      if (error instanceof AnalysisRangeError) {
        throw new GuideVisualAnalysisError(error.code);
      }
      throw error;
    }
  }

  const analysisMode = clipped ? "clipped_detail" : "full_discovery";
  const fps = clipped ? settings.detailFps : settings.discoveryFps;

  const requestHash = buildVisualRequestHash({
    videoId: video.videoId,
    videoMetadataHash: video.metadataHash,
    videoPublishedAt: video.publishedAt?.toISOString() ?? null,
    videoDuration: video.durationSeconds,
    providerId: GEMINI_PROVIDER_ID,
    modelIdentifier: settings.model,
    visualPromptVersion: VISUAL_PROMPT_VERSION,
    visualSchemaVersion: VISUAL_SCHEMA_VERSION,
    gameDataVersion: GUIDE_GAME_DATA_VERSION,
    analysisMode,
    fps,
    requestedRanges,
  });

  if (!input.force) {
    const cached = await prisma.guideVisualAnalysisResult.findUnique({
      where: { cacheKey: requestHash },
      include: { evidences: true },
    });
    if (cached?.status === "validated") {
      logVisualAnalysisEvent({
        videoId: video.videoId,
        stage: VISUAL_ANALYSIS_STAGE,
        retryReason: "cache_hit",
        terminal: true,
      });
      return {
        jobId: "cache-hit",
        cacheKey: requestHash,
        status: "cache_hit",
        evidenceCount: cached.evidences.length,
        recommendationIds: [],
        analysisMode,
        fps,
      };
    }
    // Terminal success: do not requeue paid AI for already-analyzed videos.
    if (video.analysisStatus === "analyzed") {
      const latest = await prisma.guideVisualAnalysisResult.findFirst({
        where: { videoId: video.videoId, status: "validated" },
        orderBy: { generatedAt: "desc" },
        include: { evidences: true },
      });
      if (latest) {
        logVisualAnalysisEvent({
          videoId: video.videoId,
          stage: VISUAL_ANALYSIS_STAGE,
          retryReason: "already_analyzed",
          terminal: true,
        });
        return {
          jobId: "already-analyzed",
          cacheKey: latest.cacheKey,
          status: "already_analyzed",
          evidenceCount: latest.evidences.length,
          recommendationIds: [],
          analysisMode,
          fps,
        };
      }
    }
  }

  const recentRateLimit = await prisma.guideVisualAnalysisJob.findFirst({
    where: {
      errorCode: {
        in: ["http429", "providerRateLimited", "geminiProviderCoolingDown"],
      },
      createdAt: {
        gte: new Date(Date.now() - VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS),
      },
    },
    orderBy: { createdAt: "desc" },
    select: { id: true, createdAt: true },
  });
  if (recentRateLimit) {
    noteVisualProviderCooldown(VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS);
    throw new GuideVisualAnalysisError("providerRateLimited");
  }

  if (activeJobs.has(video.videoId)) {
    throw new GuideVisualAnalysisError("analysisAlreadyRunning");
  }

  const inflight = await prisma.guideVisualAnalysisJob.findFirst({
    where: {
      videoId: video.videoId,
      status: "running",
      startedAt: { gte: new Date(Date.now() - 30 * 60_000) },
    },
    select: { id: true },
  });
  if (inflight) {
    throw new GuideVisualAnalysisError("analysisAlreadyRunning");
  }

  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const usageToday = await prisma.guideVisualUsageLog.count({
    where: { channelId: video.channelId, createdAt: { gte: dayStart }, success: true },
  });
  if (usageToday >= video.channel.dailyAnalysisLimit) {
    throw new GuideVisualAnalysisError("channelDailyLimit");
  }

  activeJobs.add(video.videoId);
  const job = await prisma.guideVisualAnalysisJob.create({
    data: {
      videoId: video.videoId,
      requestHash,
      status: "running",
      providerId: GEMINI_PROVIDER_ID,
      modelIdentifier: settings.model,
      promptVersion: VISUAL_PROMPT_VERSION,
      schemaVersion: VISUAL_SCHEMA_VERSION,
      gameDataVersion: GUIDE_GAME_DATA_VERSION,
      rangesPayload: JSON.stringify({
        analysisMode,
        fps,
        stage: VISUAL_ANALYSIS_STAGE,
        ranges: requestedRanges ?? [],
      }),
      startedAt: new Date(),
    },
  });

  let jobMarkedSucceeded = false;
  try {
    const hints = await loadCharacterHints();
    const known = new Set(hints.map((h) => h.id));
    const fromTitle = resolveCharacterCandidates(video.title, "", hints).matchedIds;
    const targetCharacterIds =
      input.targetCharacterIds?.filter((id) => known.has(id)) ??
      (fromTitle.length > 0 ? fromTitle : hints.slice(0, 40).map((h) => h.id));

    const rangeSecondsTotal = (requestedRanges ?? []).reduce(
      (sum, range) => sum + Math.max(0, range.endSeconds - range.startSeconds),
      0,
    );
    const allowLongform = input.allowLongform !== false && !clipped;
    const wantsLongform =
      allowLongform &&
      analysisMode === "full_discovery" &&
      needsLongformFullDiscovery({
        durationSeconds: video.durationSeconds,
        fps,
        targetCharacterCount: targetCharacterIds.length,
      });

    let estimatedTokens = 0;
    let longformPlan: LongformPlan | null = null;
    if (wantsLongform) {
      try {
        longformPlan = planLongformChunks({
          videoId: video.videoId,
          durationSeconds: video.durationSeconds ?? 0,
          fps: settings.discoveryFps,
          targetCharacterCount: targetCharacterIds.length,
          maxRangeSeconds: settings.maxRangeSeconds,
        });
        estimatedTokens = longformPlan.estimatedInputTokens;
      } catch (error) {
        if (error instanceof LongformPlanningError) {
          throw new GuideVisualAnalysisError(error.code);
        }
        throw error;
      }
    } else {
      try {
        estimatedTokens = assertVisualTokenBudget({
          durationSeconds: video.durationSeconds,
          fps,
          analysisMode,
          rangeSecondsTotal,
          targetCharacterCount: targetCharacterIds.length,
        }).estimatedTokens;
      } catch (error) {
        if (
          error instanceof Error &&
          error.message === "videoTooLargeForFullDiscovery"
        ) {
          throw new GuideVisualAnalysisError("videoTooLargeForFullDiscovery");
        }
        throw error;
      }
    }

    const control = await readGlobalAiEmergencyControl();
    logVisualAnalysisEvent({
      jobId: job.id,
      videoId: video.videoId,
      stage: longformPlan ? "visual-longform" : VISUAL_ANALYSIS_STAGE,
      provider: GEMINI_PROVIDER_ID,
      controlVersion: control.version,
      estimatedTokens,
      terminal: false,
    });

    const provider = input.provider ?? new GeminiYouTubeVisualAnalysisProvider();

    let analysisResult: VideoVisualAnalysisResult;
    let analysisRawContent: string;
    let analysisModelIdentifier: string;
    let analysisUsage: Record<string, number>;
    let analysisAttempts: number;
    let finalRequestHash = requestHash;
    let finalAllowedWindows = clipped ? requestedRanges : undefined;

    if (longformPlan) {
      const longformOutcome = await runLongformChunkPipeline({
        video,
        jobId: job.id,
        plan: longformPlan,
        targetCharacterIds,
        known,
        provider,
        settings,
        baseRequest: {
          videoMetadataHash: video.metadataHash,
          videoPublishedAt: video.publishedAt?.toISOString() ?? null,
          videoDuration: video.durationSeconds,
          modelIdentifier: settings.model,
        },
      });
      analysisResult = longformOutcome.result;
      analysisRawContent = longformOutcome.rawContent;
      analysisModelIdentifier = longformOutcome.modelIdentifier;
      analysisUsage = longformOutcome.usage;
      analysisAttempts = longformOutcome.attempts;
      finalRequestHash = longformOutcome.requestHash;
      finalAllowedWindows = longformPlan.chunks.map((c) => ({
        startSeconds: c.startSeconds,
        endSeconds: c.endSeconds,
        reason: c.reason,
      }));
      await prisma.guideVisualAnalysisJob.update({
        where: { id: job.id },
        data: {
          requestHash: finalRequestHash,
          rangesPayload: JSON.stringify(
            buildLongformRangesPayload({
              plan: longformPlan,
              partialState: longformOutcome.partialState,
              chunkUsage: longformOutcome.chunkUsage,
            }),
          ),
        },
      });
    } else {
      const analysis = await provider.analyze({
        videoId: video.videoId,
        youtubeUrl: `https://www.youtube.com/watch?v=${video.videoId}`,
        channelId: video.channelId,
        title: video.title,
        publishedAt: video.publishedAt?.toISOString() ?? null,
        durationSeconds: video.durationSeconds,
        targetCharacterIds,
        requestedRanges,
        analysisMode,
        fps,
        gameDataVersion: GUIDE_GAME_DATA_VERSION,
      });
      analysisResult = analysis.result;
      analysisRawContent = analysis.rawContent;
      analysisModelIdentifier = analysis.modelIdentifier;
      analysisUsage = analysis.usage;
      analysisAttempts = analysis.attempts;
    }

    // Emergency may have flipped during provider HTTP — block persistence/publish.
    try {
      await assertEmergencyStopAllowsWork();
    } catch {
      throw new GuideVisualAnalysisError("emergencyStopped");
    }

    const validated = validateVisualAnalysisResult({
      expectedVideoId: video.videoId,
      durationSeconds: video.durationSeconds,
      allowedCharacterIds: new Set(targetCharacterIds),
      knownCharacterIds: known,
      result: analysisResult,
      allowedWindows: finalAllowedWindows,
    });

    const result = await prisma.guideVisualAnalysisResult.upsert({
      where: { cacheKey: finalRequestHash },
      create: {
        cacheKey: finalRequestHash,
        videoId: video.videoId,
        requestHash: finalRequestHash,
        providerId: provider.providerId,
        modelIdentifier: analysisModelIdentifier,
        promptVersion: VISUAL_PROMPT_VERSION,
        schemaVersion: VISUAL_SCHEMA_VERSION,
        gameDataVersion: GUIDE_GAME_DATA_VERSION,
        status: "validated",
        rawAiOutput: analysisRawContent.slice(0, 200_000),
        validatedPayload: JSON.stringify(analysisResult),
        generatedAt: new Date(),
      },
      update: {
        status: "validated",
        rawAiOutput: analysisRawContent.slice(0, 200_000),
        validatedPayload: JSON.stringify(analysisResult),
        errorCode: "",
        generatedAt: new Date(),
      },
    });

    await prisma.guideVisualEvidence.deleteMany({
      where: { analysisResultId: result.id },
    });

    const evidenceIds: string[] = [];
    for (const item of validated) {
      const evidence = await prisma.guideVisualEvidence.create({
        data: {
          analysisResultId: result.id,
          videoId: video.videoId,
          startSeconds: item.startSeconds,
          endSeconds: item.endSeconds,
          evidenceType: item.evidenceType,
          normalizedPayload: JSON.stringify({
            ...((item.normalizedPayload as object) ?? {}),
            publishableStatValues: item.publishableStatValues,
            targetCharacterIds: item.targetCharacterIds,
          }),
          exactVisibleText: item.exactVisibleText.slice(0, 200),
          confidence: item.confidence,
          validationStatus: item.validationStatus,
          approvalStatus:
            item.validationStatus === "validated" ? "pending_review" : "rejected",
          exclusionCode: item.exclusionCode,
          purposeSummary: item.purposeSummary,
          visibleTexts: {
            create: item.visibleTexts.slice(0, 40).map((text) => ({
              text: text.text.slice(0, 300),
              category: text.category,
              confidence: text.confidence,
            })),
          },
        },
      });
      evidenceIds.push(evidence.id);
      for (const characterId of item.targetCharacterIds.slice(0, 5)) {
        for (const stat of item.publishableStatValues) {
          await prisma.guideVisualExtractedClaim.create({
            data: {
              evidenceId: evidence.id,
              videoId: video.videoId,
              characterId,
              claimKey: `stat.${stat.statKey}`,
              claimPayload: JSON.stringify(stat),
              purpose: stat.purpose,
              confidence: stat.confidence,
            },
          });
        }
      }
    }

    await prisma.guideVisualAnalysisJob.update({
      where: { id: job.id },
      data: {
        status: "succeeded",
        attempts: analysisAttempts,
        tokenUsage: JSON.stringify(analysisUsage),
        completedAt: new Date(),
      },
    });
    jobMarkedSucceeded = true;
    await prisma.guideVideo.update({
      where: { videoId: video.videoId },
      data: { analysisStatus: "analyzed", lastAnalyzedAt: new Date() },
    });
    await prisma.guideVisualUsageLog.create({
      data: {
        channelId: video.channelId,
        videoId: video.videoId,
        providerId: provider.providerId,
        modelIdentifier: analysisModelIdentifier,
        success: true,
        tokenUsage: JSON.stringify(analysisUsage),
      },
    });

    // AI analysis terminal success is already recorded. Post-process never
    // calls Gemini and must not flip job status back to failed.
    const postProcess = await runVisualPostProcess({
      videoId: video.videoId,
      evidenceIds,
      jobId: job.id,
      knownCharacterIds: known,
    });
    const recommendationIds = postProcess.recommendationIds;

    // Production normal path: auto-publish when gate allows (Canary passes skipAutoPublish).
    let autoPublish: VisualAutoPublishResult | null = null;
    if (!input.skipAutoPublish) {
      const publishGate = await evaluateVisualAutoPublishGate();
      if (publishGate.allowed && recommendationIds.length > 0) {
        // Re-check emergency immediately before publish (race with admin stop).
        try {
          await assertEmergencyStopAllowsWork();
        } catch {
          throw new GuideVisualAnalysisError("emergencyStopped");
        }
        autoPublish = await autoPublishVisualRecommendations({
          evidenceIds,
          recommendationIds,
        });
      }
    }

    logVisualAnalysisEvent({
      jobId: job.id,
      videoId: video.videoId,
      stage: longformPlan ? "visual-longform" : VISUAL_ANALYSIS_STAGE,
      attempt: analysisAttempts,
      provider: GEMINI_PROVIDER_ID,
      terminal: true,
      estimatedTokens,
    });

    return {
      jobId: job.id,
      cacheKey: finalRequestHash,
      status: "validated",
      evidenceCount: validated.length,
      recommendationIds,
      analysisMode: longformPlan ? "full_discovery" : analysisMode,
      fps: longformPlan?.fps ?? fps,
      autoPublish,
    };
  } catch (error) {
    const code = resolveAnalysisErrorCode(error);
    // Never log the raw Error object (may embed request/URL/auth material).
    if (process.env.NODE_ENV !== "production") {
      logSafeFailure("build-guide-analysis", code, { videoId: video.videoId });
    }
    const failureClass = classifyVisualAnalysisFailure(code);
    if (failureClass.providerCooldown) {
      noteVisualProviderCooldown(VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS);
    }
    // Never overwrite a terminal succeeded job (post-process failures stay annotated).
    if (jobMarkedSucceeded) {
      await prisma.guideVisualAnalysisJob.update({
        where: { id: job.id },
        data: { errorCode: `postProcess:${code}` },
      });
      logVisualAnalysisEvent({
        jobId: job.id,
        videoId: video.videoId,
        stage: VISUAL_ANALYSIS_STAGE,
        retryReason: `postProcess:${code}`,
        provider: GEMINI_PROVIDER_ID,
        terminal: true,
      });
      throw new GuideVisualAnalysisError(
        code === "emergencyStopped" ? code : `postProcess:${code}`,
      );
    }
    await prisma.guideVisualAnalysisJob.update({
      where: { id: job.id },
      data: {
        status: "failed",
        errorCode: code,
        completedAt: new Date(),
      },
    });
    await prisma.guideVisualUsageLog.create({
      data: {
        channelId: video.channelId,
        videoId: video.videoId,
        providerId: GEMINI_PROVIDER_ID,
        modelIdentifier: settings.model,
        success: false,
        tokenUsage: "",
      },
    });
    logVisualAnalysisEvent({
      jobId: job.id,
      videoId: video.videoId,
      stage: VISUAL_ANALYSIS_STAGE,
      retryReason: code,
      provider: GEMINI_PROVIDER_ID,
      terminal: !failureClass.retryable,
    });
    throw new GuideVisualAnalysisError(code);
  } finally {
    activeJobs.delete(video.videoId);
  }
}

function resolveAnalysisErrorCode(error: unknown): string {
  if (error instanceof GuideVisualAnalysisError) return error.message;
  if (error instanceof VisualPostProcessError) return error.code;
  if (error instanceof LongformPlanningError) return error.code;
  if (error instanceof AnalysisRangeError) return error.code;
  if (error instanceof GeminiError) return error.code;
  if (error instanceof VisualValidationError) return error.code;
  if (error instanceof Error) {
    const maybeCode = (error as Error & { code?: unknown }).code;
    if (typeof maybeCode === "string" && /^P\d{4}$/.test(maybeCode)) {
      return `prisma${maybeCode}`;
    }
    const message = error.message;
    if (message.startsWith("postProcess:")) return message.slice("postProcess:".length);
    if (/^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(message)) return message;
    if (message.includes("Unique constraint")) return "prismaUniqueConstraint";
    if (message.includes("ON CONFLICT clause")) return "prismaMissingUniqueIndex";
    if (message.includes("Foreign key constraint")) return "prismaForeignKey";
    if (message.includes("does not exist")) return "prismaMissingTable";
    if (message.includes("AbortError") || message.includes("aborted")) {
      return "timeout";
    }
  }
  return "analysisFailed";
}

async function runLongformChunkPipeline(input: {
  video: {
    videoId: string;
    channelId: string;
    title: string;
    publishedAt: Date | null;
    durationSeconds: number | null;
    metadataHash: string;
  };
  jobId: string;
  plan: LongformPlan;
  targetCharacterIds: string[];
  known: Set<string>;
  provider: VideoVisualAnalysisProvider;
  settings: ReturnType<typeof geminiVideoSettings>;
  baseRequest: {
    videoMetadataHash: string;
    videoPublishedAt: string | null;
    videoDuration: number | null;
    modelIdentifier: string;
  };
}): Promise<{
  result: VideoVisualAnalysisResult;
  rawContent: string;
  modelIdentifier: string;
  usage: Record<string, number>;
  attempts: number;
  requestHash: string;
  partialState: ReturnType<typeof buildLongformPartialState>;
  chunkUsage: LongformChunkUsageRecord[];
}> {
  const completedIndexes: number[] = [];
  const chunkResults: Array<{
    chunkIndex: number;
    result: VideoVisualAnalysisResult;
  }> = [];
  const rawParts: string[] = [];
  const usageTotals: Record<string, number> = {};
  const chunkUsage: LongformChunkUsageRecord[] = [];
  let attemptsUsed = 0;
  let failedChunkIndex: number | null = null;
  let failedCode: string | null = null;
  let emergency = false;
  let rateLimited = false;

  const persistLongformProgress = async (
    state: ReturnType<typeof buildLongformPartialState>,
  ) => {
    await prisma.guideVisualAnalysisJob.update({
      where: { id: input.jobId },
      data: {
        rangesPayload: JSON.stringify(
          buildLongformRangesPayload({
            plan: input.plan,
            partialState: state,
            chunkUsage,
          }),
        ),
      },
    });
  };

  for (const chunk of input.plan.chunks) {
    try {
      await assertEmergencyStopAllowsWork();
    } catch {
      emergency = true;
      failedChunkIndex = chunk.chunkIndex;
      failedCode = "emergencyStopped";
      break;
    }
    try {
      assertVisualProviderNotCoolingDown();
    } catch {
      rateLimited = true;
      failedChunkIndex = chunk.chunkIndex;
      failedCode = "geminiProviderCoolingDown";
      break;
    }

    const chunkRanges = [
      {
        startSeconds: chunk.startSeconds,
        endSeconds: chunk.endSeconds,
        reason: chunk.reason,
      },
    ];
    const chunkHash = buildVisualRequestHash({
      videoId: input.video.videoId,
      videoMetadataHash: input.baseRequest.videoMetadataHash,
      videoPublishedAt: input.baseRequest.videoPublishedAt,
      videoDuration: input.baseRequest.videoDuration,
      providerId: GEMINI_PROVIDER_ID,
      modelIdentifier: input.baseRequest.modelIdentifier,
      visualPromptVersion: VISUAL_PROMPT_VERSION,
      visualSchemaVersion: VISUAL_SCHEMA_VERSION,
      gameDataVersion: GUIDE_GAME_DATA_VERSION,
      analysisMode: "clipped_detail",
      fps: input.plan.fps,
      requestedRanges: chunkRanges,
    });

    const cached = await prisma.guideVisualAnalysisResult.findUnique({
      where: { cacheKey: chunkHash },
      select: {
        status: true,
        validatedPayload: true,
        rawAiOutput: true,
        modelIdentifier: true,
      },
    });

    if (cached?.status === "validated" && cached.validatedPayload) {
      try {
        const parsed = JSON.parse(
          cached.validatedPayload,
        ) as VideoVisualAnalysisResult;
        chunkResults.push({ chunkIndex: chunk.chunkIndex, result: parsed });
        completedIndexes.push(chunk.chunkIndex);
        rawParts.push(cached.rawAiOutput.slice(0, 20_000));
        chunkUsage.push(
          buildLongformChunkUsageRecord({
            chunkIndex: chunk.chunkIndex,
            rangeStart: chunk.startSeconds,
            rangeEnd: chunk.endSeconds,
            estimatedTokens: chunk.estimatedTokens,
            usage: null,
            attempts: 0,
            cacheHit: true,
            provider: GEMINI_PROVIDER_ID,
            requestHash: chunkHash,
          }),
        );
        logVisualAnalysisEvent({
          jobId: input.jobId,
          videoId: input.video.videoId,
          stage: "visual-longform-chunk",
          attempt: chunk.chunkIndex + 1,
          retryReason: "chunk_cache_hit",
          estimatedTokens: chunk.estimatedTokens,
          terminal: false,
        });
        continue;
      } catch {
        // Fall through to re-analyze this chunk.
      }
    }

    try {
      const analysis = await input.provider.analyze({
        videoId: input.video.videoId,
        youtubeUrl: `https://www.youtube.com/watch?v=${input.video.videoId}`,
        channelId: input.video.channelId,
        title: input.video.title,
        publishedAt: input.video.publishedAt?.toISOString() ?? null,
        durationSeconds: input.video.durationSeconds,
        targetCharacterIds: input.targetCharacterIds,
        requestedRanges: chunkRanges,
        analysisMode: "clipped_detail",
        fps: input.plan.fps,
        gameDataVersion: GUIDE_GAME_DATA_VERSION,
      });

      // Re-check after HTTP response before accepting work.
      try {
        await assertEmergencyStopAllowsWork();
      } catch {
        emergency = true;
        failedChunkIndex = chunk.chunkIndex;
        failedCode = "emergencyStopped";
        // Keep paid-call usage if the HTTP already completed.
        chunkUsage.push(
          buildLongformChunkUsageRecord({
            chunkIndex: chunk.chunkIndex,
            rangeStart: chunk.startSeconds,
            rangeEnd: chunk.endSeconds,
            estimatedTokens: chunk.estimatedTokens,
            usage: analysis.usage,
            attempts: analysis.attempts,
            cacheHit: false,
            provider: GEMINI_PROVIDER_ID,
            requestHash: chunkHash,
          }),
        );
        break;
      }

      validateVisualAnalysisResult({
        expectedVideoId: input.video.videoId,
        durationSeconds: input.video.durationSeconds,
        allowedCharacterIds: new Set(input.targetCharacterIds),
        knownCharacterIds: input.known,
        result: analysis.result,
        allowedWindows: chunkRanges,
      });

      await prisma.guideVisualAnalysisResult.upsert({
        where: { cacheKey: chunkHash },
        create: {
          cacheKey: chunkHash,
          videoId: input.video.videoId,
          requestHash: chunkHash,
          providerId: input.provider.providerId,
          modelIdentifier: analysis.modelIdentifier,
          promptVersion: VISUAL_PROMPT_VERSION,
          schemaVersion: VISUAL_SCHEMA_VERSION,
          gameDataVersion: GUIDE_GAME_DATA_VERSION,
          status: "validated",
          rawAiOutput: analysis.rawContent.slice(0, 200_000),
          validatedPayload: JSON.stringify(analysis.result),
          generatedAt: new Date(),
        },
        update: {
          status: "validated",
          rawAiOutput: analysis.rawContent.slice(0, 200_000),
          validatedPayload: JSON.stringify(analysis.result),
          errorCode: "",
          generatedAt: new Date(),
        },
      });

      chunkResults.push({
        chunkIndex: chunk.chunkIndex,
        result: analysis.result,
      });
      completedIndexes.push(chunk.chunkIndex);
      rawParts.push(analysis.rawContent.slice(0, 20_000));
      attemptsUsed = Math.max(attemptsUsed, analysis.attempts);
      for (const [key, value] of Object.entries(analysis.usage)) {
        usageTotals[key] = (usageTotals[key] ?? 0) + value;
      }
      chunkUsage.push(
        buildLongformChunkUsageRecord({
          chunkIndex: chunk.chunkIndex,
          rangeStart: chunk.startSeconds,
          rangeEnd: chunk.endSeconds,
          estimatedTokens: chunk.estimatedTokens,
          usage: analysis.usage,
          attempts: analysis.attempts,
          cacheHit: false,
          provider: GEMINI_PROVIDER_ID,
          requestHash: chunkHash,
        }),
      );
      logVisualAnalysisEvent({
        jobId: input.jobId,
        videoId: input.video.videoId,
        stage: "visual-longform-chunk",
        attempt: chunk.chunkIndex + 1,
        provider: GEMINI_PROVIDER_ID,
        estimatedTokens: chunk.estimatedTokens,
        terminal: false,
      });
    } catch (error) {
      const code = resolveAnalysisErrorCode(error);
      failedChunkIndex = chunk.chunkIndex;
      failedCode = code;
      chunkUsage.push(
        buildLongformChunkUsageRecord({
          chunkIndex: chunk.chunkIndex,
          rangeStart: chunk.startSeconds,
          rangeEnd: chunk.endSeconds,
          estimatedTokens: chunk.estimatedTokens,
          usage: null,
          attempts: 0,
          cacheHit: false,
          provider: GEMINI_PROVIDER_ID,
          requestHash: chunkHash,
        }),
      );
      if (
        code === "emergencyStopped" ||
        code === "EMERGENCY_STOPPED"
      ) {
        emergency = true;
      }
      if (
        code === "http429" ||
        code === "providerRateLimited" ||
        code === "geminiProviderCoolingDown"
      ) {
        rateLimited = true;
        noteVisualProviderCooldown(VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS);
      }
      break;
    }
  }

  const partialState = buildLongformPartialState({
    plan: input.plan,
    completedChunkIndexes: completedIndexes,
    failedChunkIndex,
    failedCode,
    emergency,
    rateLimited,
  });

  if (!isLongformPublishable(partialState)) {
    // Persist observed chunkUsage even on partial/abort (no invented actuals).
    await persistLongformProgress(partialState);
    // Do not merge/publish incomplete discovery. Cached chunks remain for resume.
    throw new GuideVisualAnalysisError(
      partialState.failedCode ?? "longformPartialFailure",
    );
  }

  // Emergency again before merge (no new HTTP, but no publish of stale work).
  try {
    await assertEmergencyStopAllowsWork();
  } catch {
    await persistLongformProgress({
      ...partialState,
      status: "aborted_emergency",
      failedCode: "emergencyStopped",
    });
    throw new GuideVisualAnalysisError("emergencyStopped");
  }

  const reduced = reduceLongformChunkResults(
    input.video.videoId,
    chunkResults,
  );

  const requestHash = buildVisualRequestHash({
    videoId: input.video.videoId,
    videoMetadataHash: input.baseRequest.videoMetadataHash,
    videoPublishedAt: input.baseRequest.videoPublishedAt,
    videoDuration: input.baseRequest.videoDuration,
    providerId: GEMINI_PROVIDER_ID,
    modelIdentifier: input.baseRequest.modelIdentifier,
    visualPromptVersion: VISUAL_PROMPT_VERSION,
    visualSchemaVersion: VISUAL_SCHEMA_VERSION,
    gameDataVersion: GUIDE_GAME_DATA_VERSION,
    analysisMode: "clipped_detail",
    fps: input.plan.fps,
    requestedRanges: input.plan.chunks.map((c) => ({
      startSeconds: c.startSeconds,
      endSeconds: c.endSeconds,
    })),
  });

  return {
    result: reduced.result,
    rawContent: rawParts.join("\n---\n").slice(0, 200_000),
    modelIdentifier: input.baseRequest.modelIdentifier,
    usage: {
      ...usageTotals,
      longformChunks: input.plan.chunks.length,
      longformMergeLevels: reduced.levels,
      longformMergeTokensEst: reduced.estimatedMergeTokens,
    },
    attempts: Math.max(1, attemptsUsed),
    requestHash,
    partialState,
    chunkUsage,
  };
}

function buildLongformRangesPayload(input: {
  plan: LongformPlan;
  partialState: ReturnType<typeof buildLongformPartialState>;
  chunkUsage: LongformChunkUsageRecord[];
}): Record<string, unknown> {
  return {
    analysisMode: "longform_chunked",
    fps: input.plan.fps,
    stage: "visual-longform",
    longform: {
      ...input.partialState,
      chunkUsage: input.chunkUsage,
    },
    plan: {
      version: input.plan.version,
      chunkCount: input.plan.chunks.length,
      estimatedInputTokens: input.plan.estimatedInputTokens,
      estimatedAiCalls: input.plan.estimatedAiCalls,
      chunks: input.plan.chunks.map((c) => ({
        i: c.chunkIndex,
        s: c.startSeconds,
        e: c.endSeconds,
        tokens: c.estimatedTokens,
      })),
    },
    /** Top-level mirror for easy admin/ops parsing (same records as longform.chunkUsage). */
    chunkUsage: input.chunkUsage,
  };
}

/**
 * Production pending batch (stock).
 *
 * NOT for Limited Batch Canary — use `runLimitedBatchCanary` instead.
 * Stock path: allowLongform=false; does not set skipAutoPublish (Production =
 * auto-publish when evaluateVisualAutoPublishGate allows). May scan uncovered queue.
 *
 * タイトルに「【原神】」を含み未解析の公開動画を解析する。
 * mode=uncoveredCharacters: 育成ガイド寄り・未カバーキャラ優先で1キャラ1本。
 * Covered = CharacterBuildRecommendation status != rejected（pending_review 含む）。
 * analysis succeeded + postProcess failed は AI キューから外れ、recoverPostProcessFailures で復旧する。
 */
export async function analyzePendingGenshinVideos(input: {
  limit?: number;
  mode?: "newest" | "uncoveredCharacters";
  /** 全キャラ実行時にチャンネル日次上限を引き上げる（既定 true for uncovered） */
  raiseDailyLimitTo?: number;
} = {}): Promise<{
  titleMarker: string;
  mode: "newest" | "uncoveredCharacters";
  limit: number;
  attempted: number;
  succeeded: number;
  failed: number;
  /**
   * @deprecated Use remainingEligibleVideos. This is eligible-queue remainder, NOT master uncovered count.
   */
  remainingUncoveredEstimate: number | null;
  remainingEligibleVideos: number | null;
  eligiblePendingVideos: number | null;
  coverage: CoverageMetrics;
  results: Array<{
    videoId: string;
    title: string;
    characterId?: string | null;
    ok: boolean;
    status?: string;
    evidenceCount?: number;
    recommendationIds?: string[];
    error?: string;
  }>;
  note: string;
}> {
  const mode = input.mode ?? "newest";
  const limit = Math.min(Math.max(input.limit ?? 1, 1), 10);
  const raiseTo =
    input.raiseDailyLimitTo ??
    (mode === "uncoveredCharacters" ? 300 : undefined);

  if (raiseTo != null && raiseTo > 0) {
    await prisma.guideChannel.updateMany({
      where: {
        enabled: true,
        permissionStatus: "approved_for_processing",
        dailyAnalysisLimit: { lt: raiseTo },
      },
      data: { dailyAnalysisLimit: raiseTo },
    });
  }

  const pending = await prisma.guideVideo.findMany({
    where: {
      title: { contains: GENSIN_VIDEO_TITLE_MARKER },
      analysisStatus: { not: "analyzed" },
      privacyStatus: "public",
      channel: {
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    },
    orderBy: [{ publishedAt: "desc" }, { updatedAt: "desc" }],
    take: mode === "uncoveredCharacters" ? 500 : limit,
    select: { videoId: true, title: true },
  });

  let selected: Array<{ videoId: string; title: string; characterId?: string | null }> =
    [];
  let remainingEligibleVideos: number | null = null;
  let eligiblePendingVideos: number | null = null;

  if (mode === "uncoveredCharacters") {
    const hints = await loadCharacterHints();
    const coveredRows = await prisma.characterBuildRecommendation.findMany({
      where: { status: { not: "rejected" } },
      select: { characterId: true },
    });
    const coveredIds = new Set(coveredRows.map((r) => r.characterId));
    const built = buildUncoveredEligibleQueue({
      pendingVideos: pending,
      hints,
      coveredIds,
      limit,
    });
    selected = built.selected;
    eligiblePendingVideos = built.eligiblePendingVideos;
    remainingEligibleVideos = built.remainingEligibleVideos;
  } else {
    selected = pending.slice(0, limit).map((v) => ({ ...v, characterId: null }));
    eligiblePendingVideos = pending.length;
    remainingEligibleVideos = Math.max(0, pending.length - limit);
  }

  const results: Array<{
    videoId: string;
    title: string;
    characterId?: string | null;
    ok: boolean;
    status?: string;
    evidenceCount?: number;
    recommendationIds?: string[];
    error?: string;
  }> = [];

  for (const video of selected) {
    try {
      await assertEmergencyStopAllowsWork();
    } catch {
      results.push({
        videoId: video.videoId,
        title: video.title,
        characterId: video.characterId,
        ok: false,
        error: "emergencyStopped",
      });
      break;
    }
    try {
      const outcome = await analyzeVideoVisuals({
        videoId: video.videoId,
        targetCharacterIds: video.characterId ? [video.characterId] : undefined,
        // Pending/batch must not auto-start expensive long-form.
        allowLongform: false,
      });
      results.push({
        videoId: video.videoId,
        title: video.title,
        characterId: video.characterId,
        ok: true,
        status: outcome.status,
        evidenceCount: outcome.evidenceCount,
        recommendationIds: outcome.recommendationIds,
      });
    } catch (error) {
      const code =
        error instanceof GuideVisualAnalysisError
          ? error.code
          : error instanceof Error
            ? error.message
            : "analysisFailed";
      results.push({
        videoId: video.videoId,
        title: video.title,
        characterId: video.characterId,
        ok: false,
        error: code,
      });
      if (
        shouldAbortPendingBatch(code) ||
        code === "channelDailyLimit" ||
        code === "geminiDisabled" ||
        code === "geminiVideoDisabled" ||
        code === "geminiNotConfigured" ||
        code === "analysisAlreadyRunning" ||
        code === "emergencyStopped" ||
        code === "EMERGENCY_STOPPED" ||
        code === "videoTooLargeForFullDiscovery"
      ) {
        break;
      }
      // Non-retryable failures: continue to next video, never tight-retry same one.
      if (!classifyVisualAnalysisFailure(code).retryable) {
        continue;
      }
    }
  }

  const succeeded = results.filter((r) => r.ok).length;
  const failed = results.filter((r) => !r.ok).length;
  const attempted = results.length;
  const coverage = await getCoverageMetrics({ eligibleLimit: limit });
  // Compat alias: historically misnamed; equals eligible-queue remainder only.
  const remainingUncoveredEstimate = remainingEligibleVideos;

  return {
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
    mode,
    limit,
    attempted,
    succeeded,
    failed,
    remainingUncoveredEstimate,
    remainingEligibleVideos,
    eligiblePendingVideos,
    coverage,
    results,
    note:
      mode === "uncoveredCharacters"
        ? attempted === 0
          ? "未カバーキャラを確認しましたが、解析対象はありませんでした。タイトルに「【原神】」を含み未解析・公開・許可済みチャンネルの育成ガイド動画が無い、または該当キャラが既に推奨（rejected以外）でカバー済みの可能性があります。postProcess失敗の復旧は recoverPostProcessFailures を使います（AI再解析しません）。HTTPタイムアウト回避のため1回あたり最大10件です。"
          : "未カバーキャラの育成ガイド動画を優先解析しました。HTTPタイムアウト回避のため1回あたり最大10件です。管理画面の全キャラボタンは残件がなくなるまで繰り返します。公開には証拠確認→構造化→publishが必要です。"
        : "解析成功分は証拠（pending_review）と推奨ドラフトまで作成済みです。公開するには証拠確認→構造化編集→publish が必要です。",
  };
}

