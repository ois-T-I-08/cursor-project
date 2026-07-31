import { retryDelayMs } from "./state-machine";
import type { SafeProviderError } from "./provider-error";

export type RetryAttempt<T> =
  | { ok: true; value: T; attempts: number }
  | {
      ok: false;
      error: SafeProviderError;
      attempts: number;
      exhausted: boolean;
    };

export async function runWithFiniteRetry<T>(input: {
  operation: () => Promise<T>;
  maxAttempts: number;
  sleep?: (milliseconds: number) => Promise<void>;
  baseSeconds?: number;
}): Promise<RetryAttempt<T>> {
  const maxAttempts = Math.max(1, Math.min(10, Math.trunc(input.maxAttempts)));
  const sleep =
    input.sleep ??
    ((milliseconds: number) =>
      new Promise<void>((resolve) => setTimeout(resolve, milliseconds)));
  let lastError: SafeProviderError | null = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return { ok: true, value: await input.operation(), attempts: attempt };
    } catch (error) {
      if (!isSafeProviderError(error)) throw error;
      lastError = error;
      if (!error.retryable || attempt === maxAttempts) {
        return {
          ok: false,
          error,
          attempts: attempt,
          exhausted: error.retryable && attempt === maxAttempts,
        };
      }
      await sleep(retryDelayMs(attempt, input.baseSeconds));
    }
  }
  if (!lastError) throw new Error("retryInvariant");
  return {
    ok: false,
    error: lastError,
    attempts: maxAttempts,
    exhausted: true,
  };
}

function isSafeProviderError(error: unknown): error is SafeProviderError {
  return (
    error instanceof Error &&
    error.name === "SafeProviderError" &&
    "retryable" in error &&
    typeof error.retryable === "boolean"
  );
}

