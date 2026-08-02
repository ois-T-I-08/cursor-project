import "server-only";

import {
  DeepSeekError,
  assertAllowedDeepSeekModel,
  clampEnvNumber,
} from "@/lib/ai/deepseek-json-client";

export function isDeepSeekGuideAnalysisEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return env.DEEPSEEK_GUIDE_ANALYSIS_ENABLED === "true";
}

export function deepSeekGuideAnalysisSettings(
  env: Readonly<Record<string, string | undefined>> = process.env,
) {
  if (!isDeepSeekGuideAnalysisEnabled(env)) {
    throw new DeepSeekError("guideAnalysisDisabled", false);
  }
  const apiKey =
    env.DEEPSEEK_GUIDE_ANALYSIS_API_KEY?.trim() ||
    env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) throw new DeepSeekError("notConfigured", false);
  const model =
    env.DEEPSEEK_GUIDE_ANALYSIS_MODEL?.trim() || "deepseek-v4-flash";
  assertAllowedDeepSeekModel(model);
  return {
    apiKey,
    model,
    timeoutMs: clampEnvNumber(
      env.DEEPSEEK_GUIDE_ANALYSIS_TIMEOUT_MS,
      60_000,
      5_000,
      120_000,
    ),
    maxAttempts: clampEnvNumber(
      env.DEEPSEEK_GUIDE_ANALYSIS_MAX_ATTEMPTS,
      3,
      1,
      3,
    ),
  };
}
