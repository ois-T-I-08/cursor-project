import "server-only";

import { prisma } from "@/lib/db";
import { buildVisualRequestHash } from "./cache-key";
import { loadCharacterHints, resolveCharacterCandidates } from "./character-match";
import {
  mergeVisualRecommendationsDeterministic,
  mergeVisualRecommendationsWithDeepSeek,
} from "./deepseek-visual-merge";
import { GeminiError } from "./gemini-settings";
import { GeminiYouTubeVisualAnalysisProvider } from "./gemini-youtube-provider";
import { geminiVideoSettings } from "./gemini-settings";
import type { VideoVisualAnalysisProvider } from "./visual-provider";
import { validateVisualAnalysisResult } from "./visual-validator";
import {
  GUIDE_GAME_DATA_VERSION,
  GEMINI_PROVIDER_ID,
  VISUAL_PROMPT_VERSION,
  VISUAL_SCHEMA_VERSION,
} from "./versions";

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
    requestedRanges: input.requestedRanges,
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
      rangesPayload: JSON.stringify(input.requestedRanges ?? []),
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
      requestedRanges: input.requestedRanges,
      gameDataVersion: GUIDE_GAME_DATA_VERSION,
    });

    const validated = validateVisualAnalysisResult({
      expectedVideoId: video.videoId,
      durationSeconds: video.durationSeconds,
      allowedCharacterIds: new Set(targetCharacterIds),
      knownCharacterIds: known,
      result: analysis.result,
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

    return {
      jobId: job.id,
      cacheKey: requestHash,
      status: "validated",
      evidenceCount: validated.length,
      recommendationIds,
    };
  } catch (error) {
    const code =
      error instanceof GuideVisualAnalysisError ||
      error instanceof GeminiError ||
      (error instanceof Error && /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message))
        ? (error as Error).message
        : "analysisFailed";
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

    const recommendation = await prisma.characterBuildRecommendation.create({
      data: {
        characterId,
        status: "pending_review",
        origin: "single_video",
        contextPayload: JSON.stringify(merged.context),
        mainStatsPayload: JSON.stringify(merged.mainStats),
        priorityPayload: JSON.stringify(merged.substatPriority),
        targetsPayload: JSON.stringify(merged.targets),
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

function safeJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}
