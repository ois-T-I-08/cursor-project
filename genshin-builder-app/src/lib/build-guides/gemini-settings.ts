import "server-only";

import { clampEnvNumber } from "@/lib/ai/deepseek-json-client";

/** Documented YouTube URL video models (ai.google.dev video understanding). */
export const GEMINI_ALLOWED_VIDEO_MODELS = new Set([
  "gemini-3.6-flash",
  "gemini-2.5-flash",
  "gemini-2.5-pro",
  "gemini-2.0-flash",
]);

export class GeminiError extends Error {
  constructor(
    public readonly code: string,
    public readonly retryable: boolean,
  ) {
    super(code);
    this.name = "GeminiError";
  }
}

export function geminiVideoSettings(): {
  apiKey: string;
  model: string;
  timeoutMs: number;
  maxAttempts: number;
  maxDurationSeconds: number;
} {
  if (process.env.GEMINI_VIDEO_ANALYSIS_ENABLED !== "true") {
    throw new GeminiError("geminiVideoDisabled", false);
  }
  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) throw new GeminiError("geminiNotConfigured", false);
  const model = process.env.GEMINI_VIDEO_ANALYSIS_MODEL?.trim() || "";
  if (!model || !GEMINI_ALLOWED_VIDEO_MODELS.has(model)) {
    throw new GeminiError("unsupportedGeminiModel", false);
  }
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
  };
}
