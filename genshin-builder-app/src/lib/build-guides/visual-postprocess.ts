import "server-only";

import { z } from "zod";
import { prisma } from "@/lib/db";
import {
  mergeVisualRecommendationsDeterministic,
  type VisualMergeOutput,
} from "./deepseek-visual-merge";
import { GUIDE_GAME_DATA_VERSION } from "./versions";
import { logVisualAnalysisEvent } from "./visual-analysis-safety";
import { sanitizeStatPriority } from "./visual-stat-sanitize";

export type PostProcessErrorCode =
  | "invalidProviderResponse"
  | "schemaValidationFailed"
  | "parseFailed"
  | "normalizationFailed"
  | "entityResolutionFailed"
  | "mergeFailed"
  | "persistenceFailed"
  | "unknownPostProcessFailure";

export class VisualPostProcessError extends Error {
  constructor(
    public readonly code: PostProcessErrorCode,
    public readonly retryable = false,
  ) {
    super(code);
    this.name = "VisualPostProcessError";
  }
}

export { sanitizeStatPriority };

/** Transient persistence only — deterministic failures never retry. */
export const POST_PROCESS_MAX_ATTEMPTS = 2;

export function classifyPostProcessError(error: unknown): {
  code: PostProcessErrorCode;
  retryable: boolean;
} {
  if (error instanceof VisualPostProcessError) {
    return { code: error.code, retryable: error.retryable };
  }
  if (error instanceof z.ZodError) {
    return { code: "schemaValidationFailed", retryable: false };
  }
  if (error instanceof SyntaxError) {
    return { code: "parseFailed", retryable: false };
  }
  if (error instanceof Error) {
    const maybeCode = (error as Error & { code?: unknown }).code;
    if (typeof maybeCode === "string" && /^P\d{4}$/.test(maybeCode)) {
      const transient = ["P1001", "P1002", "P1017", "P2024"].includes(maybeCode);
      return { code: "persistenceFailed", retryable: transient };
    }
    const message = error.message;
    if (message.includes("Unique constraint") || message.includes("Foreign key")) {
      return { code: "persistenceFailed", retryable: false };
    }
    if (
      message.includes("Timed out") ||
      message.includes("Connection") ||
      message.includes("ECONNRESET") ||
      message.includes("socket hang up")
    ) {
      return { code: "persistenceFailed", retryable: true };
    }
    if (message === "entityResolutionFailed") {
      return { code: "entityResolutionFailed", retryable: false };
    }
    if (message === "mergeFailed" || message.includes("merge")) {
      return { code: "mergeFailed", retryable: false };
    }
  }
  return { code: "unknownPostProcessFailure", retryable: false };
}

function safeJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

async function annotateJobPostProcess(input: {
  jobId: string | null;
  videoId: string;
  status: "succeeded" | "failed";
  code: string;
  attempts: number;
}): Promise<void> {
  if (!input.jobId) return;
  const job = await prisma.guideVisualAnalysisJob.findUnique({
    where: { id: input.jobId },
    select: { rangesPayload: true, status: true, errorCode: true },
  });
  if (!job || job.status !== "succeeded") return;

  let ranges: Record<string, unknown> = {};
  try {
    ranges = JSON.parse(job.rangesPayload || "{}") as Record<string, unknown>;
  } catch {
    ranges = {};
  }
  ranges.postProcess = {
    status: input.status,
    code: input.code,
    attempts: input.attempts,
  };

  await prisma.guideVisualAnalysisJob.update({
    where: { id: input.jobId },
    data: {
      // Never flip succeeded → failed.
      errorCode:
        input.status === "failed"
          ? `postProcess:${input.code}`
          : job.errorCode.startsWith("postProcess:")
            ? ""
            : job.errorCode,
      rangesPayload: JSON.stringify(ranges),
    },
  });
}

/**
 * Create pending recommendations from already-persisted validated evidences.
 * No Gemini / provider calls.
 */
export async function runVisualPostProcess(input: {
  videoId: string;
  evidenceIds: string[];
  jobId?: string | null;
  knownCharacterIds?: Set<string>;
}): Promise<{ recommendationIds: string[]; attempts: number }> {
  let lastError: unknown = null;
  for (let attempt = 1; attempt <= POST_PROCESS_MAX_ATTEMPTS; attempt++) {
    try {
      const recommendationIds = await createRecommendationsOnce(input);
      await annotateJobPostProcess({
        jobId: input.jobId ?? null,
        videoId: input.videoId,
        status: "succeeded",
        code: "",
        attempts: attempt,
      });
      logVisualAnalysisEvent({
        jobId: input.jobId ?? undefined,
        videoId: input.videoId,
        stage: "visual-postprocess",
        attempt,
        terminal: true,
      });
      return { recommendationIds, attempts: attempt };
    } catch (error) {
      lastError = error;
      const classified = classifyPostProcessError(error);
      logVisualAnalysisEvent({
        jobId: input.jobId ?? undefined,
        videoId: input.videoId,
        stage: "visual-postprocess",
        attempt,
        retryReason: classified.code,
        terminal: !classified.retryable || attempt >= POST_PROCESS_MAX_ATTEMPTS,
      });
      if (!classified.retryable || attempt >= POST_PROCESS_MAX_ATTEMPTS) {
        await annotateJobPostProcess({
          jobId: input.jobId ?? null,
          videoId: input.videoId,
          status: "failed",
          code: classified.code,
          attempts: attempt,
        });
        throw new VisualPostProcessError(classified.code, false);
      }
      await new Promise((r) => setTimeout(r, 250 * attempt));
    }
  }
  const classified = classifyPostProcessError(lastError);
  throw new VisualPostProcessError(classified.code, false);
}

async function createRecommendationsOnce(input: {
  videoId: string;
  evidenceIds: string[];
  knownCharacterIds?: Set<string>;
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
    }>(evidence.normalizedPayload, {});
    const characterIds = (payload.targetCharacterIds ?? []).filter((id) => {
      if (typeof id !== "string" || !id.trim()) return false;
      if (id === "[object Object]") return false;
      return true;
    });
    for (const characterId of characterIds) {
      // Prefer known master IDs when provided; keep unresolved IDs so merge
      // can still produce pending candidates (admin can fix mapping).
      if (
        input.knownCharacterIds &&
        input.knownCharacterIds.size > 0 &&
        !input.knownCharacterIds.has(characterId)
      ) {
        continue;
      }
      const list = byCharacter.get(characterId) ?? [];
      list.push(evidence);
      byCharacter.set(characterId, list);
    }
  }

  if (byCharacter.size === 0 && evidences.length > 0) {
    // Fallback: if strict known-filter emptied everything, retry without filter
    // so numeric/slug mismatches do not discard validated evidences.
    if (input.knownCharacterIds && input.knownCharacterIds.size > 0) {
      return createRecommendationsOnce({
        videoId: input.videoId,
        evidenceIds: input.evidenceIds,
      });
    }
    throw new VisualPostProcessError("entityResolutionFailed", false);
  }

  const recommendationIds: string[] = [];
  for (const [characterId, list] of byCharacter) {
    const mergeInput = {
      characterId,
      visualEvidences: list.map((evidence) => {
        const payload = safeJson<{
          publishableStatValues?: unknown[];
          recommendedMainStats?: unknown;
          statPriority?: unknown;
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
          statPriority: sanitizeStatPriority(payload.statPriority),
          confidence: evidence.confidence,
        };
      }),
      allowedVideoIds: [input.videoId],
      allowedCharacterIds: [characterId],
      gameDataVersion: GUIDE_GAME_DATA_VERSION,
    };

    // Deterministic only — never call Gemini/DeepSeek here (no AI rebill).
    let merged: VisualMergeOutput;
    try {
      merged = mergeVisualRecommendationsDeterministic(mergeInput);
      merged = {
        ...merged,
        substatPriority: sanitizeStatPriority(merged.substatPriority),
      };
    } catch (error) {
      if (error instanceof z.ZodError) {
        throw new VisualPostProcessError("mergeFailed", false);
      }
      throw new VisualPostProcessError(
        classifyPostProcessError(error).code,
        false,
      );
    }

    const { buildStructuredPayloadFromEvidences } = await import(
      "./public-recommendation-normalize"
    );
    let structuredPayload: string;
    try {
      structuredPayload = buildStructuredPayloadFromEvidences(
        list.map((e) => ({
          videoId: e.videoId,
          normalizedPayload: e.normalizedPayload,
        })),
      );
    } catch {
      throw new VisualPostProcessError("normalizationFailed", false);
    }

    try {
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
          notes: [...merged.caveats, merged.adminSummary]
            .filter(Boolean)
            .join("\n"),
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
    } catch (error) {
      const classified = classifyPostProcessError(error);
      throw new VisualPostProcessError(classified.code, classified.retryable);
    }
  }
  return recommendationIds;
}

/**
 * Re-run post-process from persisted evidences. Never calls Gemini.
 */
export async function retryVisualPostProcessOnly(videoId: string): Promise<{
  recommendationIds: string[];
  attempts: number;
  jobId: string | null;
}> {
  const job = await prisma.guideVisualAnalysisJob.findFirst({
    where: { videoId, status: "succeeded" },
    orderBy: { completedAt: "desc" },
    select: { id: true, requestHash: true },
  });
  const result = await prisma.guideVisualAnalysisResult.findFirst({
    where: {
      videoId,
      status: "validated",
      ...(job?.requestHash ? { requestHash: job.requestHash } : {}),
    },
    orderBy: { generatedAt: "desc" },
    select: { id: true },
  });
  if (!result) {
    throw new VisualPostProcessError("invalidProviderResponse", false);
  }
  const evidences = await prisma.guideVisualEvidence.findMany({
    where: {
      analysisResultId: result.id,
      validationStatus: "validated",
      approvalStatus: { not: "rejected" },
    },
    select: { id: true },
  });
  if (evidences.length === 0) {
    throw new VisualPostProcessError("invalidProviderResponse", false);
  }

  const outcome = await runVisualPostProcess({
    videoId,
    evidenceIds: evidences.map((e) => e.id),
    jobId: job?.id ?? null,
  });
  return {
    recommendationIds: outcome.recommendationIds,
    attempts: outcome.attempts,
    jobId: job?.id ?? null,
  };
}
