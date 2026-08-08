/**
 * Sequential stock production batch runner (concurrency = 1).
 * Used by analyzePendingGenshinVideos — not Limited Batch Canary.
 */
import {
  classifyVisualAnalysisFailure,
  shouldAbortPendingBatch,
} from "./visual-analysis-safety";

export type PendingBatchVideo = {
  videoId: string;
  title: string;
  characterId?: string | null;
};

export type PendingBatchAnalyzeOutcome = {
  status: string;
  evidenceCount?: number;
  recommendationIds?: string[];
};

export type PendingBatchItemResult = PendingBatchVideo & {
  ok: boolean;
  status?: string;
  evidenceCount?: number;
  recommendationIds?: string[];
  error?: string;
};

export type PendingBatchAnalyzeFn = (input: {
  videoId: string;
  targetCharacterIds?: string[];
  /** Production stock enables long-form for >80k videos. */
  allowLongform: true;
}) => Promise<PendingBatchAnalyzeOutcome>;

/**
 * Codes that stop the remainder of the stock pending batch.
 * Rate-limit / emergency / cooldown via shouldAbortPendingBatch;
 * plus hard stop gates that are not classified as abortBatch.
 */
export function shouldStopStockPendingBatch(code: string): boolean {
  if (shouldAbortPendingBatch(code)) return true;
  return (
    code === "channelDailyLimit" ||
    code === "geminiDisabled" ||
    code === "geminiVideoDisabled" ||
    code === "geminiNotConfigured" ||
    code === "analysisAlreadyRunning" ||
    code === "emergencyStopped" ||
    code === "EMERGENCY_STOPPED" ||
    code === "geminiProviderCoolingDown"
  );
}

/**
 * Run selected pending videos sequentially (concurrency=1).
 * On abort codes: push failed item and do not start remaining items.
 * On other non-retryable failures: continue to next item.
 * Production path: always allowLongform=true (reuses existing long-form pipeline).
 * Does not set skipAutoPublish — Production auto-publish gates apply unchanged.
 */
export async function runSequentialPendingGenshinBatch(input: {
  selected: PendingBatchVideo[];
  analyze: PendingBatchAnalyzeFn;
  assertEmergencyAllowsWork: () => Promise<void>;
}): Promise<PendingBatchItemResult[]> {
  const results: PendingBatchItemResult[] = [];

  for (const video of input.selected) {
    try {
      await input.assertEmergencyAllowsWork();
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
      const outcome = await input.analyze({
        videoId: video.videoId,
        targetCharacterIds: video.characterId
          ? [video.characterId]
          : undefined,
        allowLongform: true,
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
        error &&
        typeof error === "object" &&
        "code" in error &&
        typeof (error as { code: unknown }).code === "string"
          ? (error as { code: string }).code
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
      if (shouldStopStockPendingBatch(code)) {
        break;
      }
      if (!classifyVisualAnalysisFailure(code).retryable) {
        continue;
      }
      // Retryable-but-non-abort: still do not tight-retry same item in stock batch.
      continue;
    }
  }

  return results;
}
