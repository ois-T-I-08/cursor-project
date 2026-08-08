import "server-only";

import {
  DeepSeekError,
  assertAllowedDeepSeekModel,
  clampEnvNumber,
} from "@/lib/ai/deepseek-json-client";

export function isDeepSeekDailyPlanEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return (
    env.DEEPSEEK_ENABLED === "true" &&
    env.DEEPSEEK_DAILY_PLAN_ENABLED === "true"
  );
}

export function configuredDailyPlanModel(
  env: Readonly<Record<string, string | undefined>> = process.env,
): string {
  return env.DEEPSEEK_MODEL?.trim() || "deepseek-v4-flash";
}

export function deepSeekDailyPlanSettings(
  env: Readonly<Record<string, string | undefined>> = process.env,
) {
  if (!isDeepSeekDailyPlanEnabled(env)) {
    throw new DeepSeekError("dailyPlanDisabled", false);
  }
  const apiKey =
    env.DEEPSEEK_API_KEY?.trim() ||
    env.DEEPSEEK_DAILY_PLAN_API_KEY?.trim() ||
    env.DEEPSEEK_GUIDE_ANALYSIS_API_KEY?.trim();
  if (!apiKey) throw new DeepSeekError("notConfigured", false);
  const model = configuredDailyPlanModel(env);
  assertAllowedDeepSeekModel(model);
  return {
    apiKey,
    model,
    timeoutMs: clampEnvNumber(env.DEEPSEEK_TIMEOUT_MS, 45_000, 5_000, 60_000),
    maxAttempts: clampEnvNumber(env.DEEPSEEK_MAX_ATTEMPTS, 3, 1, 3),
  };
}
