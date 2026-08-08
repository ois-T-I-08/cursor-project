import "server-only";

/**
 * Visual / Gemini analysis retry + token guards (Audit Retry Safety).
 * No secrets / prompts logged here.
 */

/** Empirically calibrated from production jobs (~92 tokens/s @ 1fps full video). */
export const VISUAL_TOKENS_PER_SECOND_AT_1FPS = 92;

/** Hard ceiling before calling Gemini full_discovery. */
export const VISUAL_PROMPT_TOKEN_HARD_MAX = 80_000;

/** Provider-wide cooldown after 429 when Retry-After is absent. */
export const VISUAL_PROVIDER_DEFAULT_COOLDOWN_MS = 60_000;

const RATE_LIMIT_CODES = new Set([
  "http429",
  "providerRateLimited",
  "geminiProviderCoolingDown",
]);

const NON_RETRYABLE_CODES = new Set([
  "invalidJson",
  "invalidResult",
  "invalidEnvelope",
  "invalidYoutubeHost",
  "invalidGeminiHost",
  "unsupportedGeminiModel",
  "geminiNotConfigured",
  "geminiVideoDisabled",
  "geminiDisabled",
  "videoTooLong",
  "videoTooLargeForFullDiscovery",
  "responseTooLarge",
  "responseTruncated",
  "emergencyStopped",
  "EMERGENCY_STOPPED",
  "permissionNotApproved",
  "channelDisabled",
  "videoNotPublic",
  "videoNotFound",
  "channelDailyLimit",
  "analysisAlreadyRunning",
  "rangeTooLong",
  "tooManyRanges",
  "invalidRange",
  "analysisFailed",
  "longformTooManyChunks",
  "longformTooManyAiCalls",
  "longformPartialFailure",
  "longformChunkExceedsHardMax",
  "mergeFailed",
  "schemaValidationFailed",
  "entityResolutionFailed",
  "invalidProviderResponse",
  "normalizationFailed",
  "parseFailed",
  "persistenceFailed",
  "unknownPostProcessFailure",
]);

export type VisualFailureClass = Readonly<{
  retryable: boolean;
  abortBatch: boolean;
  providerCooldown: boolean;
}>;

export function classifyVisualAnalysisFailure(code: string): VisualFailureClass {
  if (RATE_LIMIT_CODES.has(code) || code === "http429") {
    return { retryable: true, abortBatch: true, providerCooldown: true };
  }
  if (code.startsWith("http5") || code === "timeout" || code === "networkError") {
    return { retryable: true, abortBatch: false, providerCooldown: false };
  }
  if (NON_RETRYABLE_CODES.has(code) || code.startsWith("prisma")) {
    return {
      retryable: false,
      abortBatch:
        code === "emergencyStopped" || code === "EMERGENCY_STOPPED",
      providerCooldown: false,
    };
  }
  // Unknown → fail closed (do not tight-retry).
  return { retryable: false, abortBatch: false, providerCooldown: false };
}

export function estimateVisualPromptTokens(input: {
  durationSeconds: number | null;
  fps: number;
  analysisMode: "full_discovery" | "clipped_detail";
  rangeSecondsTotal?: number;
  targetCharacterCount: number;
}): number {
  const fps = Math.max(0.1, input.fps);
  const videoSeconds =
    input.analysisMode === "clipped_detail"
      ? Math.max(1, input.rangeSecondsTotal ?? 0)
      : Math.max(1, input.durationSeconds ?? 0);
  const media = Math.round(videoSeconds * fps * VISUAL_TOKENS_PER_SECOND_AT_1FPS);
  const promptOverhead = 2_000 + input.targetCharacterCount * 8;
  return media + promptOverhead;
}

export function assertVisualTokenBudget(input: {
  durationSeconds: number | null;
  fps: number;
  analysisMode: "full_discovery" | "clipped_detail";
  rangeSecondsTotal?: number;
  targetCharacterCount: number;
  hardMax?: number;
}): { estimatedTokens: number } {
  const estimatedTokens = estimateVisualPromptTokens(input);
  const hardMax = input.hardMax ?? VISUAL_PROMPT_TOKEN_HARD_MAX;
  if (estimatedTokens > hardMax) {
    throw new Error("videoTooLargeForFullDiscovery");
  }
  return { estimatedTokens };
}

export function parseRetryAfterMs(
  header: string | null | undefined,
  nowMs: number = Date.now(),
): number | null {
  if (!header) return null;
  const trimmed = header.trim();
  if (!trimmed) return null;
  if (/^\d+$/.test(trimmed)) {
    const seconds = Number(trimmed);
    if (!Number.isFinite(seconds) || seconds < 0) return null;
    return Math.min(3_600_000, Math.round(seconds * 1_000));
  }
  const dateMs = Date.parse(trimmed);
  if (!Number.isFinite(dateMs)) return null;
  return Math.min(3_600_000, Math.max(0, dateMs - nowMs));
}

export function geminiHttpRetryDelayMs(input: {
  attempt: number;
  status: number;
  retryAfterHeader?: string | null;
  random?: () => number;
}): number {
  const random = input.random ?? Math.random;
  const retryAfter = parseRetryAfterMs(input.retryAfterHeader ?? null);
  if (retryAfter != null) {
    return retryAfter + Math.floor(random() * 250);
  }
  const attempt = Math.max(1, Math.min(10, Math.trunc(input.attempt)));
  const base = input.status === 429 ? 5_000 : 500;
  const exp = Math.min(120_000, base * 2 ** (attempt - 1));
  const jitter = Math.floor(random() * Math.min(1_000, exp * 0.2));
  return exp + jitter;
}

/** Process-local cooldown (supplements DB recent-429 checks). */
let providerCooldownUntilMs = 0;

export function noteVisualProviderCooldown(delayMs: number): void {
  const until = Date.now() + Math.max(1_000, Math.min(3_600_000, Math.trunc(delayMs)));
  providerCooldownUntilMs = Math.max(providerCooldownUntilMs, until);
}

export function clearVisualProviderCooldownForTest(): void {
  providerCooldownUntilMs = 0;
}

export function getVisualProviderCooldownRemainingMs(
  nowMs: number = Date.now(),
): number {
  return Math.max(0, providerCooldownUntilMs - nowMs);
}

export function assertVisualProviderNotCoolingDown(
  nowMs: number = Date.now(),
): void {
  if (getVisualProviderCooldownRemainingMs(nowMs) > 0) {
    throw new Error("geminiProviderCoolingDown");
  }
}

export function shouldAbortPendingBatch(code: string): boolean {
  return classifyVisualAnalysisFailure(code).abortBatch;
}

export function logVisualAnalysisEvent(input: {
  jobId?: string;
  videoId: string;
  stage: string;
  attempt?: number;
  retryReason?: string;
  nextRetryMs?: number;
  provider?: string;
  controlVersion?: number;
  terminal?: boolean;
  estimatedTokens?: number;
}): void {
  console.info("[visual-analysis]", {
    jobId: input.jobId ?? null,
    videoId: input.videoId,
    stage: input.stage,
    attempt: input.attempt ?? null,
    retryReason: input.retryReason ?? null,
    nextRetryMs: input.nextRetryMs ?? null,
    provider: input.provider ?? "gemini-visual",
    controlVersion: input.controlVersion ?? null,
    terminal: input.terminal ?? null,
    estimatedTokens: input.estimatedTokens ?? null,
  });
}
