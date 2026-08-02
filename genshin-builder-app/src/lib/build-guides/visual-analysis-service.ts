import "server-only";

import { prisma } from "@/lib/db";
import { buildVisualRequestHash } from "./cache-key";
import { loadCharacterHints, resolveCharacterCandidates } from "./character-match";
import {
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
} from "./character-match-logic";
import {
  mergeVisualRecommendationsDeterministic,
  mergeVisualRecommendationsWithDeepSeek,
} from "./deepseek-visual-merge";
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
  autoPublishVisualRecommendations,
  isVisualAutoPublishEnabled,
} from "./visual-auto-publish";
import type { VisualAutoPublishResult } from "./visual-auto-publish";

export class GuideVisualAnalysisError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "GuideVisualAnalysisError";
  }
}

const activeJobs = new Set<string>();

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
  }

  if (activeJobs.has(video.videoId)) {
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
        ranges: requestedRanges ?? [],
      }),
      startedAt: new Date(),
    },
  });

  try {
    const hints = await loadCharacterHints();
    const known = new Set(hints.map((h) => h.id));
    const fromTitle = resolveCharacterCandidates(video.title, "", hints).matchedIds;
    const targetCharacterIds =
      input.targetCharacterIds?.filter((id) => known.has(id)) ??
      (fromTitle.length > 0 ? fromTitle : hints.slice(0, 40).map((h) => h.id));

    const provider = input.provider ?? new GeminiYouTubeVisualAnalysisProvider();
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

    const validated = validateVisualAnalysisResult({
      expectedVideoId: video.videoId,
      durationSeconds: video.durationSeconds,
      allowedCharacterIds: new Set(targetCharacterIds),
      knownCharacterIds: known,
      result: analysis.result,
      allowedWindows: clipped ? requestedRanges : undefined,
    });

    const result = await prisma.guideVisualAnalysisResult.upsert({
      where: { cacheKey: requestHash },
      create: {
        cacheKey: requestHash,
        videoId: video.videoId,
        requestHash,
        providerId: provider.providerId,
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
        attempts: analysis.attempts,
        tokenUsage: JSON.stringify(analysis.usage),
        completedAt: new Date(),
      },
    });
    await prisma.guideVideo.update({
      where: { videoId: video.videoId },
      data: { analysisStatus: "analyzed", lastAnalyzedAt: new Date() },
    });
    await prisma.guideVisualUsageLog.create({
      data: {
        channelId: video.channelId,
        videoId: video.videoId,
        providerId: provider.providerId,
        modelIdentifier: analysis.modelIdentifier,
        success: true,
        tokenUsage: JSON.stringify(analysis.usage),
      },
    });

    const recommendationIds = await createPendingRecommendationsFromVisuals({
      videoId: video.videoId,
      evidenceIds,
    });

    let autoPublish: VisualAutoPublishResult | null = null;
    if (isVisualAutoPublishEnabled() && recommendationIds.length > 0) {
      autoPublish = await autoPublishVisualRecommendations({
        evidenceIds,
        recommendationIds,
      });
    }

    return {
      jobId: job.id,
      cacheKey: requestHash,
      status: "validated",
      evidenceCount: validated.length,
      recommendationIds,
      analysisMode,
      fps,
      autoPublish,
    };
  } catch (error) {
    const code = resolveAnalysisErrorCode(error);
    if (process.env.NODE_ENV !== "production") {
      console.error("[build-guide-analysis]", video.videoId, code, error);
    }
    await prisma.guideVisualAnalysisJob.update({
      where: { id: job.id },
      data: { status: "failed", errorCode: code, completedAt: new Date() },
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
    throw new GuideVisualAnalysisError(code);
  } finally {
    activeJobs.delete(video.videoId);
  }
}

function resolveAnalysisErrorCode(error: unknown): string {
  if (error instanceof GuideVisualAnalysisError) return error.message;
  if (error instanceof AnalysisRangeError) return error.code;
  if (error instanceof GeminiError) return error.code;
  if (error instanceof VisualValidationError) return error.code;
  if (error instanceof Error) {
    const maybeCode = (error as Error & { code?: unknown }).code;
    if (typeof maybeCode === "string" && /^P\d{4}$/.test(maybeCode)) {
      return `prisma${maybeCode}`;
    }
    const message = error.message;
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

async function createPendingRecommendationsFromVisuals(input: {
  videoId: string;
  evidenceIds: string[];
}): Promise<string[]> {
  const evidences = await prisma.guideVisualEvidence.findMany({
    where: {
      id: { in: input.evidenceIds },
      validationStatus: "validated",
      approvalStatus: { not: "rejected" },
    },
  });
  if (evidences.length === 0) return [];

  const byCharacter = new Map<string, typeof evidences>();
  for (const evidence of evidences) {
    const payload = safeJson<{
      targetCharacterIds?: string[];
      publishableStatValues?: unknown[];
    }>(evidence.normalizedPayload, {});
    const characterIds = payload.targetCharacterIds ?? [];
    for (const characterId of characterIds) {
      const list = byCharacter.get(characterId) ?? [];
      list.push(evidence);
      byCharacter.set(characterId, list);
    }
  }

  const recommendationIds: string[] = [];
  for (const [characterId, list] of byCharacter) {
    const mergeInput = {
      characterId,
      visualEvidences: list.map((evidence) => {
        const payload = safeJson<{
          publishableStatValues?: unknown[];
          recommendedMainStats?: unknown;
          statPriority?: string[];
        }>(evidence.normalizedPayload, {});
        return {
          evidenceId: evidence.id,
          videoId: evidence.videoId,
          startSeconds: evidence.startSeconds,
          endSeconds: evidence.endSeconds,
          evidenceType: evidence.evidenceType,
          visibleTexts: [evidence.exactVisibleText],
          statValues: payload.publishableStatValues ?? [],
          mainStats: payload.recommendedMainStats ?? null,
          statPriority: payload.statPriority ?? [],
          confidence: evidence.confidence,
        };
      }),
      allowedVideoIds: [input.videoId],
      allowedCharacterIds: [characterId],
      gameDataVersion: GUIDE_GAME_DATA_VERSION,
    };

    let merged;
    try {
      merged = await mergeVisualRecommendationsWithDeepSeek(mergeInput);
    } catch {
      merged = mergeVisualRecommendationsDeterministic(mergeInput);
    }

    const { buildStructuredPayloadFromEvidences } = await import(
      "./public-recommendation-normalize"
    );
    const structuredPayload = buildStructuredPayloadFromEvidences(
      list.map((e) => ({
        videoId: e.videoId,
        normalizedPayload: e.normalizedPayload,
      })),
    );

    const recommendation = await prisma.characterBuildRecommendation.create({
      data: {
        characterId,
        status: "pending_review",
        origin: "single_video",
        contextPayload: JSON.stringify(merged.context),
        mainStatsPayload: JSON.stringify(merged.mainStats),
        priorityPayload: JSON.stringify(merged.substatPriority),
        targetsPayload: JSON.stringify(merged.targets),
        structuredPayload,
        overallConfidence: merged.overallConfidence,
        notes: [...merged.caveats, merged.adminSummary].filter(Boolean).join("\n"),
      },
    });

    for (const evidence of list) {
      await prisma.recommendationVisualContribution.create({
        data: {
          recommendationId: recommendation.id,
          evidenceId: evidence.id,
          videoId: evidence.videoId,
          startSeconds: evidence.startSeconds,
          endSeconds: evidence.endSeconds,
          exactVisibleText: evidence.exactVisibleText.slice(0, 200),
          contributionRole: "primary",
          decision: "adopted",
          decisionSummary: "auto-candidate from validated visual evidence",
          usedInPublishedResult: false,
        },
      });
    }
    recommendationIds.push(recommendation.id);
  }
  return recommendationIds;
}

/**
 * タイトルに「【原神】」を含み未解析の公開動画を解析する。
 * mode=uncoveredCharacters: 育成ガイド寄り・未カバーキャラ優先で1キャラ1本。
 * 各動画の成功時は証拠 + キャラ別 pending 推奨ドラフトまで作成する。
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
  remainingUncoveredEstimate: number | null;
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
  let remainingUncoveredEstimate: number | null = null;

  if (mode === "uncoveredCharacters") {
    const hints = await loadCharacterHints();
    const coveredRows = await prisma.characterBuildRecommendation.findMany({
      where: { status: { not: "rejected" } },
      distinct: ["characterId"],
      select: { characterId: true },
    });
    const claimed = new Set(coveredRows.map((r) => r.characterId));
    const queue: Array<{ videoId: string; title: string; characterId: string }> =
      [];
    for (const video of pending) {
      if (!isCharacterBuildGuideTitle(video.title)) continue;
      const characterId = resolvePrimaryCharacterFromTitle(video.title, hints);
      if (!characterId || claimed.has(characterId)) continue;
      claimed.add(characterId);
      queue.push({ ...video, characterId });
    }
    remainingUncoveredEstimate = Math.max(0, queue.length - limit);
    selected = queue.slice(0, limit);
  } else {
    selected = pending.slice(0, limit).map((v) => ({ ...v, characterId: null }));
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
      const outcome = await analyzeVideoVisuals({
        videoId: video.videoId,
        targetCharacterIds: video.characterId ? [video.characterId] : undefined,
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
        code === "channelDailyLimit" ||
        code === "geminiDisabled" ||
        code === "analysisAlreadyRunning"
      ) {
        break;
      }
    }
  }

  const succeeded = results.filter((r) => r.ok).length;
  const failed = results.filter((r) => !r.ok).length;
  return {
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
    mode,
    limit,
    attempted: results.length,
    succeeded,
    failed,
    remainingUncoveredEstimate,
    results,
    note:
      mode === "uncoveredCharacters"
        ? "未カバーキャラの育成ガイド動画を優先解析しました。HTTPタイムアウト回避のため1回あたり最大10件です。管理画面の全キャラボタンは残件がなくなるまで繰り返します。公開には証拠確認→構造化→publishが必要です。"
        : "解析成功分は証拠（pending_review）と推奨ドラフトまで作成済みです。公開するには証拠確認→構造化編集→publish が必要です。",
  };
}

function safeJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}
