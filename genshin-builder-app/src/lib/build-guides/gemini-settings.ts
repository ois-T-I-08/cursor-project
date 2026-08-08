import "server-only";

import { clampEnvNumber } from "@/lib/ai/deepseek-json-client";

/**
 * Documented YouTube URL video models (ai.google.dev video understanding).
 *
 * Primary / default: gemini-3.6-flash
 *
 * gemini-2.5-flash / gemini-2.5-pro remain allowed as temporary fallbacks only.
 * Google scheduled retirement: 2026-10-16. Do not use as the primary default.
 *
 * Removed: gemini-2.0-flash (retired 2026-06-01).
 */
export const GEMINI_ALLOWED_VIDEO_MODELS = new Set([
  "gemini-3.6-flash",
  // Temporary fallback until 2026-10-16 retirement — not a default.
  "gemini-2.5-flash",
  // Temporary fallback until 2026-10-16 retirement — not a default.
  "gemini-2.5-pro",
]);

export const GEMINI_PRIMARY_VIDEO_MODEL = "gemini-3.6-flash";

export class GeminiError extends Error {
  constructor(
    public readonly code: string,
    public readonly retryable: boolean,
    /** Hint for Retry-After / computed backoff (ms). */
    public readonly retryAfterMs?: number,
  ) {
    super(code);
    this.name = "GeminiError";
  }
}

export type GeminiVideoSettings = {
  apiKey: string;
  model: string;
  timeoutMs: number;
  maxAttempts: number;
  maxDurationSeconds: number;
  discoveryFps: number;
  detailFps: number;
  maxDetailFps: number;
  maxRangeSeconds: number;
  maxRangesPerRequest: number;
};

export function geminiVideoSettings(): GeminiVideoSettings {
  if (process.env.GEMINI_VIDEO_ANALYSIS_ENABLED !== "true") {
    throw new GeminiError("geminiVideoDisabled", false);
  }
  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) throw new GeminiError("geminiNotConfigured", false);
  const model = process.env.GEMINI_VIDEO_ANALYSIS_MODEL?.trim() || "";
  if (!model || !GEMINI_ALLOWED_VIDEO_MODELS.has(model)) {
    throw new GeminiError("unsupportedGeminiModel", false);
  }

  const maxDetailFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_MAX_DETAIL_FPS,
    5,
    1,
    24,
  );
  const discoveryFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_DISCOVERY_FPS,
    1,
    1,
    maxDetailFps,
  );
  const detailFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_DETAIL_FPS,
    3,
    1,
    maxDetailFps,
  );

  return {
    apiKey,
    model,
    timeoutMs: clampEnvNumber(
      process.env.GEMINI_VIDEO_ANALYSIS_TIMEOUT_MS,
      180_000,
      10_000,
      600_000,
    ),
    maxAttempts: clampEnvNumber(
      process.env.GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS,
      2,
      1,
      3,
    ),
    maxDurationSeconds: clampEnvNumber(
      process.env.GEMINI_VIDEO_MAX_DURATION_SECONDS,
      3600,
      60,
      7200,
    ),
    discoveryFps,
    detailFps,
    maxDetailFps,
    maxRangeSeconds: clampEnvNumber(
      process.env.GEMINI_VIDEO_MAX_RANGE_SECONDS,
      180,
      5,
      900,
    ),
    maxRangesPerRequest: clampEnvNumber(
      process.env.GEMINI_VIDEO_MAX_RANGES_PER_REQUEST,
      5,
      1,
      10,
    ),
  };
}

/** Public cost hints for admin UI (no secrets). */
export function geminiVideoCostHints(): {
  primaryModel: string;
  discoveryFps: number;
  detailFps: number;
  maxDetailFps: number;
  estimatedDetailCostMultiplier: number;
  note: string;
} {
  const maxDetailFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_MAX_DETAIL_FPS,
    5,
    1,
    24,
  );
  const discoveryFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_DISCOVERY_FPS,
    1,
    1,
    maxDetailFps,
  );
  const detailFps = clampEnvNumber(
    process.env.GEMINI_VIDEO_DETAIL_FPS,
    3,
    1,
    maxDetailFps,
  );
  const multiplier =
    discoveryFps > 0 ? Math.round((detailFps / discoveryFps) * 10) / 10 : detailFps;
  return {
    primaryModel: GEMINI_PRIMARY_VIDEO_MODEL,
    discoveryFps,
    detailFps,
    maxDetailFps,
    estimatedDetailCostMultiplier: multiplier,
    note: `一次探索は約 ${discoveryFps} FPS。指定時間帯の詳細解析は約 ${detailFps} FPS（おおよそ ${multiplier} 倍のフレーム量）。`,
  };
}
