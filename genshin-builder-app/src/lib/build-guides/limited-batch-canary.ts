import "server-only";

import { prisma } from "@/lib/db";
import { readGlobalAiEmergencyControl } from "@/lib/ai/global-ai-emergency";
import { buildVisualRequestHash } from "./cache-key";
import {
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
} from "./character-match-logic";
import { loadCharacterHints } from "./character-match";
import { geminiVideoSettings } from "./gemini-settings";
import {
  assertVisualProviderNotCoolingDown,
  getVisualProviderCooldownRemainingMs,
  shouldAbortPendingBatch,
  VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS,
} from "./visual-analysis-safety";
import {
  analyzeVideoVisuals,
  GuideVisualAnalysisError,
} from "./visual-analysis-service";
import {
  assertLongformCostGuard,
  LongformPlanningError,
  needsLongformFullDiscovery,
  planLongformChunks,
} from "./visual-longform";

/** Canary planning range — analyze path still uses geminiVideoSettings.maxRangeSeconds. */
const LIMITED_BATCH_PLAN_MAX_RANGE_SECONDS = 360;
import {
  GEMINI_PROVIDER_ID,
  GUIDE_GAME_DATA_VERSION,
  VISUAL_PROMPT_VERSION,
  VISUAL_SCHEMA_VERSION,
} from "./versions";

/** Hard cap — Limited Batch Canary never exceeds this. */
export const LIMITED_BATCH_CANARY_MAX_ITEMS = 3;

/** Fixed concurrency — sequential only. */
export const LIMITED_BATCH_CANARY_CONCURRENCY = 1;

export class LimitedBatchCanaryError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "LimitedBatchCanaryError";
  }
}

export type LimitedBatchItemStatus =
  | "succeeded"
  | "failed"
  | "skipped"
  | "aborted_before_start"
  | "not_attempted";

export type LimitedBatchItemResult = {
  videoId: string;
  longform: boolean;
  status: LimitedBatchItemStatus;
  errorCode: string | null;
  skipReason: string | null;
  characterId: string | null;
  providerCalls: number;
  retries: number;
  cacheHit: boolean;
  usage: {
    promptTokenCount: number | null;
    candidatesTokenCount: number | null;
    totalTokenCount: number | null;
  } | null;
  publishDelta: number;
  analysisStatus: string | null;
};

export type LimitedBatchCanaryResult = {
  kind: "limited_batch_canary";
  maxItems: typeof LIMITED_BATCH_CANARY_MAX_ITEMS;
  concurrency: typeof LIMITED_BATCH_CANARY_CONCURRENCY;
  force: false;
  skipAutoPublish: true;
  allowLongform: true;
  requested: string[];
  eligible: string[];
  attempted: number;
  succeeded: number;
  failed: number;
  skipped: number;
  aborted: boolean;
  abortCode: string | null;
  completedItems: string[];
  remainingItems: string[];
  providerCalls: number;
  retries: number;
  http429: number;
  cacheHits: number;
  publishCount: number;
  items: LimitedBatchItemResult[];
};

export type LimitedBatchAnalyzeOutcome = {
  status: string;
  evidenceCount?: number;
  recommendationIds?: string[];
  autoPublish?: { publishedCount?: number } | null;
  providerCalls?: number;
  retries?: number;
  cacheHit?: boolean;
  usage?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
  } | null;
  publishDelta?: number;
};

export type LimitedBatchCanaryDeps = {
  readEmergency: () => Promise<{ emergencyStopped: boolean; version: number }>;
  assertProviderNotCoolingDown: () => void;
  getProviderCooldownRemainingMs: () => number;
  loadHints: () => Promise<Array<{ id: string; name: string }>>;
  loadCoveredCharacterIds: () => Promise<Set<string>>;
  loadVideo: (videoId: string) => Promise<{
    videoId: string;
    title: string;
    privacyStatus: string;
    analysisStatus: string;
    durationSeconds: number | null;
    metadataHash: string;
    publishedAt: Date | null;
    channel: {
      enabled: boolean;
      permissionStatus: string;
    };
  } | null>;
  countRunningJobs: (videoId: string) => Promise<number>;
  countRecent429: (videoId: string) => Promise<number>;
  hasValidatedCache: (cacheKey: string) => Promise<boolean>;
  /**
   * Paid analysis. Harness always invokes with force:false, skipAutoPublish:true,
   * allowLongform:true — deps must not accept overrides from callers.
   */
  analyze: (input: {
    videoId: string;
    targetCharacterIds?: string[];
    allowLongform: true;
    force: false;
    skipAutoPublish: true;
  }) => Promise<LimitedBatchAnalyzeOutcome>;
};

function defaultDeps(): LimitedBatchCanaryDeps {
  return {
    readEmergency: async () => {
      const c = await readGlobalAiEmergencyControl();
      return {
        emergencyStopped: c.emergencyStopped,
        version: c.version,
      };
    },
    assertProviderNotCoolingDown: () => assertVisualProviderNotCoolingDown(),
    getProviderCooldownRemainingMs: () => getVisualProviderCooldownRemainingMs(),
    loadHints: () => loadCharacterHints(),
    loadCoveredCharacterIds: async () => {
      const rows = await prisma.characterBuildRecommendation.findMany({
        where: { status: { not: "rejected" } },
        select: { characterId: true },
      });
      return new Set(rows.map((r) => r.characterId));
    },
    loadVideo: async (videoId) => {
      const video = await prisma.guideVideo.findUnique({
        where: { videoId },
        include: { channel: true },
      });
      if (!video) return null;
      return {
        videoId: video.videoId,
        title: video.title,
        privacyStatus: video.privacyStatus,
        analysisStatus: video.analysisStatus,
        durationSeconds: video.durationSeconds,
        metadataHash: video.metadataHash,
        publishedAt: video.publishedAt,
        channel: {
          enabled: video.channel.enabled,
          permissionStatus: video.channel.permissionStatus,
        },
      };
    },
    countRunningJobs: (videoId) =>
      prisma.guideVisualAnalysisJob.count({
        where: {
          videoId,
          status: "running",
          startedAt: { gte: new Date(Date.now() - 30 * 60_000) },
        },
      }),
    countRecent429: (videoId) =>
      prisma.guideVisualAnalysisJob.count({
        where: {
          videoId,
          errorCode: {
            in: [
              "http429",
              "providerRateLimited",
              "geminiProviderCoolingDown",
            ],
          },
          createdAt: {
            gte: new Date(Date.now() - VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS),
          },
        },
      }),
    hasValidatedCache: async (cacheKey) => {
      const cached = await prisma.guideVisualAnalysisResult.findUnique({
        where: { cacheKey },
        select: { status: true },
      });
      return cached?.status === "validated";
    },
    analyze: async (input) => {
      // Hard-lock canary safety — never forward force/skipAutoPublish from outside.
      const outcome = await analyzeVideoVisuals({
        videoId: input.videoId,
        targetCharacterIds: input.targetCharacterIds,
        force: false,
        skipAutoPublish: true,
        allowLongform: true,
      });
      const cacheHit =
        outcome.status === "cache_hit" || outcome.status === "already_analyzed";
      const publishDelta = outcome.autoPublish?.publishedCount ?? 0;
      return {
        status: outcome.status,
        evidenceCount: outcome.evidenceCount,
        recommendationIds: outcome.recommendationIds,
        autoPublish: outcome.autoPublish,
        providerCalls: cacheHit ? 0 : 1,
        retries: 0,
        cacheHit,
        usage: null,
        publishDelta,
      };
    },
  };
}

/**
 * Safety abort taxonomy for Limited Batch Canary.
 * Broader than stock shouldAbortPendingBatch for canary-only hazards.
 */
export function shouldAbortLimitedBatchCanary(code: string): boolean {
  if (shouldAbortPendingBatch(code)) return true;
  const abortCodes = new Set([
    "http429",
    "providerRateLimited",
    "geminiProviderCoolingDown",
    "emergencyStopped",
    "EMERGENCY_STOPPED",
    "unexpectedPublish",
    "publishDeltaNonZero",
    "duplicatePaidCall",
    "uncontrolledRetry",
    "costGuardViolation",
    "longformTooManyChunks",
    "longformTooManyAiCalls",
    "longformChunkExceedsHardMax",
    "orphanJob",
    "terminalCorruption",
    "unexpectedProviderException",
  ]);
  return abortCodes.has(code);
}

export type LimitedBatchEligibility =
  | {
      ok: true;
      characterId: string;
      longform: boolean;
      cacheHit: boolean;
    }
  | { ok: false; reason: string };

export function evaluateLimitedBatchEligibility(input: {
  video: NonNullable<Awaited<ReturnType<LimitedBatchCanaryDeps["loadVideo"]>>>;
  hints: Array<{ id: string; name: string }>;
  coveredIds: Set<string>;
  runningJobs: number;
  recent429: number;
  providerCoolingDown: boolean;
  cacheHit: boolean;
}): LimitedBatchEligibility {
  if (input.providerCoolingDown) {
    return { ok: false, reason: "geminiProviderCoolingDown" };
  }
  if (input.video.privacyStatus !== "public") {
    return { ok: false, reason: "videoNotPublic" };
  }
  if (!input.video.channel.enabled) {
    return { ok: false, reason: "channelDisabled" };
  }
  if (input.video.channel.permissionStatus !== "approved_for_processing") {
    return { ok: false, reason: "permissionNotApproved" };
  }
  if (!isCharacterBuildGuideTitle(input.video.title)) {
    return { ok: false, reason: "notGuideTitle" };
  }
  const characterId = resolvePrimaryCharacterFromTitle(
    input.video.title,
    input.hints,
  );
  if (!characterId) {
    return { ok: false, reason: "titleResolutionFailed" };
  }
  if (input.coveredIds.has(characterId)) {
    return { ok: false, reason: "characterAlreadyCovered" };
  }
  if (input.video.analysisStatus === "analyzed") {
    return { ok: false, reason: "alreadyAnalyzed" };
  }
  if (input.runningJobs > 0) {
    return { ok: false, reason: "analysisAlreadyRunning" };
  }
  if (input.recent429 > 0) {
    return { ok: false, reason: "recent429" };
  }
  if (input.cacheHit) {
    return { ok: false, reason: "validatedCacheHit" };
  }

  const longform = needsLongformFullDiscovery({
    durationSeconds: input.video.durationSeconds,
    fps: 1,
    targetCharacterCount: 1,
  });
  if (longform) {
    try {
      const plan = planLongformChunks({
        videoId: input.video.videoId,
        durationSeconds: input.video.durationSeconds ?? 0,
        fps: 1,
        targetCharacterCount: 1,
        maxRangeSeconds: LIMITED_BATCH_PLAN_MAX_RANGE_SECONDS,
      });
      assertLongformCostGuard(plan);
    } catch (error) {
      const code =
        error instanceof LongformPlanningError
          ? error.code
          : error instanceof Error &&
              /^[a-zA-Z][a-zA-Z0-9]+$/.test(error.message)
            ? error.message
            : "costGuardViolation";
      return { ok: false, reason: code };
    }
  }

  return { ok: true, characterId, longform, cacheHit: false };
}

function emptyItem(
  videoId: string,
  status: LimitedBatchItemStatus,
  errorCode: string | null = null,
  skipReason: string | null = null,
): LimitedBatchItemResult {
  return {
    videoId,
    longform: false,
    status,
    errorCode,
    skipReason,
    characterId: null,
    providerCalls: 0,
    retries: 0,
    cacheHit: false,
    usage: null,
    publishDelta: 0,
    analysisStatus: null,
  };
}

async function assertEmergencyOff(
  deps: LimitedBatchCanaryDeps,
): Promise<void> {
  const control = await deps.readEmergency();
  if (control.emergencyStopped) {
    throw new LimitedBatchCanaryError("emergencyStopped");
  }
}

/**
 * Limited Batch Canary — dedicated path.
 *
 * Fixed safety:
 * - maxItems ≤ 3
 * - concurrency = 1
 * - force = false
 * - skipAutoPublish = true (not overridable)
 * - allowLongform = true (cost-guarded)
 * - explicit videoIds only (no uncovered scan / scheduler)
 *
 * Do NOT use analyzePendingGenshinVideos for this canary.
 */
export async function runLimitedBatchCanary(input: {
  videoIds: string[];
  maxItems?: number;
  deps?: Partial<LimitedBatchCanaryDeps>;
}): Promise<LimitedBatchCanaryResult> {
  const maxItems = input.maxItems ?? LIMITED_BATCH_CANARY_MAX_ITEMS;
  if (!Number.isInteger(maxItems) || maxItems < 1) {
    throw new LimitedBatchCanaryError("invalidMaxItems");
  }
  if (maxItems > LIMITED_BATCH_CANARY_MAX_ITEMS) {
    throw new LimitedBatchCanaryError("maxItemsExceeded");
  }

  const requested = [...new Set(input.videoIds.map((id) => id.trim()))].filter(
    Boolean,
  );
  if (requested.length === 0) {
    throw new LimitedBatchCanaryError("emptyVideoIds");
  }
  if (requested.length > maxItems) {
    throw new LimitedBatchCanaryError("tooManyVideoIds");
  }
  // Reject anything beyond the explicit list — no scan expansion.
  const videoIds = requested.slice(0, maxItems);

  const deps: LimitedBatchCanaryDeps = {
    ...defaultDeps(),
    ...input.deps,
  };

  const items: LimitedBatchItemResult[] = videoIds.map((id) =>
    emptyItem(id, "not_attempted"),
  );
  const eligible: string[] = [];
  const completedItems: string[] = [];
  let aborted = false;
  let abortCode: string | null = null;
  let providerCalls = 0;
  let retries = 0;
  let http429 = 0;
  let cacheHits = 0;
  let publishCount = 0;
  let attempted = 0;
  let succeeded = 0;
  let failed = 0;
  let skipped = 0;

  const finish = (): LimitedBatchCanaryResult => {
    const remainingItems = items
      .filter(
        (i) =>
          i.status === "not_attempted" || i.status === "aborted_before_start",
      )
      .map((i) => i.videoId);

    return {
      kind: "limited_batch_canary",
      maxItems: LIMITED_BATCH_CANARY_MAX_ITEMS,
      concurrency: LIMITED_BATCH_CANARY_CONCURRENCY,
      force: false,
      skipAutoPublish: true,
      allowLongform: true,
      requested: videoIds,
      eligible,
      attempted,
      succeeded,
      failed,
      skipped,
      aborted,
      abortCode,
      completedItems,
      remainingItems,
      providerCalls,
      retries,
      http429,
      cacheHits,
      publishCount,
      items,
    };
  };

  try {
    await assertEmergencyOff(deps);
  } catch {
    aborted = true;
    abortCode = "emergencyStopped";
    for (const item of items) {
      item.status = "aborted_before_start";
      item.errorCode = "emergencyStopped";
    }
    return finish();
  }

  if (deps.getProviderCooldownRemainingMs() > 0) {
    aborted = true;
    abortCode = "geminiProviderCoolingDown";
    for (const item of items) {
      item.status = "aborted_before_start";
      item.errorCode = "geminiProviderCoolingDown";
    }
    return finish();
  }

  const hints = await deps.loadHints();
  const coveredIds = await deps.loadCoveredCharacterIds();
  let settings: {
    model: string;
    discoveryFps: number;
  };
  try {
    const live = geminiVideoSettings();
    settings = {
      model: live.model,
      discoveryFps: live.discoveryFps,
    };
  } catch {
    // Unit tests / unconfigured env: hash still deterministic without API key.
    settings = { model: "limited-batch-canary", discoveryFps: 1 };
  }

  for (let index = 0; index < videoIds.length; index++) {
    const videoId = videoIds[index]!;
    const item = items[index]!;

    try {
      await assertEmergencyOff(deps);
    } catch {
      aborted = true;
      abortCode = "emergencyStopped";
      for (let j = index; j < items.length; j++) {
        items[j]!.status = "aborted_before_start";
        items[j]!.errorCode = "emergencyStopped";
      }
      break;
    }

    if (deps.getProviderCooldownRemainingMs() > 0) {
      aborted = true;
      abortCode = "geminiProviderCoolingDown";
      for (let j = index; j < items.length; j++) {
        items[j]!.status = "aborted_before_start";
        items[j]!.errorCode = "geminiProviderCoolingDown";
      }
      break;
    }

    const video = await deps.loadVideo(videoId);
    if (!video) {
      item.status = "skipped";
      item.skipReason = "videoNotFound";
      item.errorCode = "videoNotFound";
      skipped += 1;
      completedItems.push(videoId);
      continue;
    }
    item.analysisStatus = video.analysisStatus;

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
      analysisMode: "full_discovery",
      fps: settings.discoveryFps,
    });

    const [runningJobs, recent429Count, cacheHit] = await Promise.all([
      deps.countRunningJobs(videoId),
      deps.countRecent429(videoId),
      deps.hasValidatedCache(requestHash),
    ]);

    const eligibility = evaluateLimitedBatchEligibility({
      video,
      hints,
      coveredIds,
      runningJobs,
      recent429: recent429Count,
      providerCoolingDown: deps.getProviderCooldownRemainingMs() > 0,
      cacheHit,
    });

    if (!eligibility.ok) {
      // Cooldown discovered at eligibility → abort remaining (not a soft skip).
      if (
        eligibility.reason === "geminiProviderCoolingDown" ||
        shouldAbortLimitedBatchCanary(eligibility.reason)
      ) {
        aborted = true;
        abortCode = eligibility.reason;
        item.status = "aborted_before_start";
        item.errorCode = eligibility.reason;
        for (let j = index + 1; j < items.length; j++) {
          items[j]!.status = "aborted_before_start";
          items[j]!.errorCode = eligibility.reason;
        }
        break;
      }
      item.status = "skipped";
      item.skipReason = eligibility.reason;
      item.errorCode = eligibility.reason;
      item.cacheHit = eligibility.reason === "validatedCacheHit";
      if (item.cacheHit) cacheHits += 1;
      skipped += 1;
      completedItems.push(videoId);
      continue;
    }

    eligible.push(videoId);
    item.longform = eligibility.longform;
    item.characterId = eligibility.characterId;

    // Mark claimed so later items in this canary don't double-target same character.
    coveredIds.add(eligibility.characterId);

    try {
      await assertEmergencyOff(deps);
      deps.assertProviderNotCoolingDown();
    } catch (error) {
      const code =
        error instanceof LimitedBatchCanaryError
          ? error.code
          : error instanceof Error && error.message === "geminiProviderCoolingDown"
            ? "geminiProviderCoolingDown"
            : "emergencyStopped";
      aborted = true;
      abortCode = code;
      item.status = "aborted_before_start";
      item.errorCode = code;
      for (let j = index + 1; j < items.length; j++) {
        items[j]!.status = "aborted_before_start";
        items[j]!.errorCode = code;
      }
      break;
    }

    attempted += 1;
    try {
      // Pre-call emergency gate (provider path also re-checks).
      await assertEmergencyOff(deps);

      const outcome = await deps.analyze({
        videoId,
        targetCharacterIds: [eligibility.characterId],
        allowLongform: true,
        force: false,
        skipAutoPublish: true,
      });

      // Post-response emergency gate before accepting side effects.
      try {
        await assertEmergencyOff(deps);
      } catch {
        aborted = true;
        abortCode = "emergencyStopped";
        item.status = "failed";
        item.errorCode = "emergencyStopped";
        failed += 1;
        completedItems.push(videoId);
        for (let j = index + 1; j < items.length; j++) {
          items[j]!.status = "aborted_before_start";
          items[j]!.errorCode = "emergencyStopped";
        }
        break;
      }

      const calls = outcome.providerCalls ?? (outcome.cacheHit ? 0 : 1);
      const itemRetries = outcome.retries ?? 0;
      const itemPublish = outcome.publishDelta ?? 0;

      item.providerCalls = calls;
      item.retries = itemRetries;
      item.cacheHit = Boolean(outcome.cacheHit);
      item.usage = outcome.usage
        ? {
            promptTokenCount: outcome.usage.promptTokenCount ?? null,
            candidatesTokenCount: outcome.usage.candidatesTokenCount ?? null,
            totalTokenCount: outcome.usage.totalTokenCount ?? null,
          }
        : null;
      item.publishDelta = itemPublish;

      providerCalls += calls;
      retries += itemRetries;
      if (item.cacheHit) cacheHits += 1;
      publishCount += itemPublish;

      if (itemPublish > 0) {
        aborted = true;
        abortCode = "unexpectedPublish";
        item.status = "failed";
        item.errorCode = "unexpectedPublish";
        failed += 1;
        completedItems.push(videoId);
        for (let j = index + 1; j < items.length; j++) {
          items[j]!.status = "aborted_before_start";
          items[j]!.errorCode = "unexpectedPublish";
        }
        break;
      }

      if (
        outcome.status === "cache_hit" ||
        outcome.status === "already_analyzed"
      ) {
        // Should have been skipped in eligibility; treat as skip if analyze returned cache.
        item.status = "skipped";
        item.skipReason = outcome.status;
        item.errorCode = outcome.status;
        skipped += 1;
        completedItems.push(videoId);
        continue;
      }

      item.status = "succeeded";
      item.errorCode = null;
      succeeded += 1;
      completedItems.push(videoId);
    } catch (error) {
      const code =
        error instanceof GuideVisualAnalysisError
          ? error.code
          : error instanceof LimitedBatchCanaryError
            ? error.code
            : error instanceof Error &&
                /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message)
              ? error.message
              : "unexpectedProviderException";

      item.status = "failed";
      item.errorCode = code;
      failed += 1;
      completedItems.push(videoId);

      if (code === "http429") http429 += 1;

      if (shouldAbortLimitedBatchCanary(code)) {
        aborted = true;
        abortCode = code;
        for (let j = index + 1; j < items.length; j++) {
          items[j]!.status = "aborted_before_start";
          items[j]!.errorCode = code;
        }
        break;
      }
      // Non-abort taxonomy: continue to next item (explicit continue policy).
    }
  }

  return finish();
}
