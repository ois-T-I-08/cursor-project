import "server-only";

import {
  DeepSeekError,
  assertAllowedDeepSeekModel,
  clampEnvNumber,
} from "@/lib/ai/deepseek-json-client";

export function deepSeekGuideSettings(): {
  apiKey: string;
  model: string;
  timeoutMs: number;
  maxAttempts: number;
} {
  if (process.env.DEEPSEEK_GUIDE_ANALYSIS_ENABLED !== "true") {
    throw new DeepSeekError("guideAnalysisDisabled", false);
  }
  const apiKey =
    process.env.DEEPSEEK_GUIDE_ANALYSIS_API_KEY?.trim() ||
    process.env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) throw new DeepSeekError("notConfigured", false);
  const model =
    process.env.DEEPSEEK_GUIDE_ANALYSIS_MODEL?.trim() || "deepseek-v4-pro";
  assertAllowedDeepSeekModel(model);
  return {
    apiKey,
    model,
    timeoutMs: clampEnvNumber(
      process.env.DEEPSEEK_GUIDE_ANALYSIS_TIMEOUT_MS,
      60_000,
      5_000,
      120_000,
    ),
    maxAttempts: clampEnvNumber(
      process.env.DEEPSEEK_GUIDE_ANALYSIS_MAX_ATTEMPTS,
      3,
      1,
      3,
    ),
  };
}
