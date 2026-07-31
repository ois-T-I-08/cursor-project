export type SafeProviderErrorCode =
  | "AUTH_NOT_CONFIGURED"
  | "AUTH_REJECTED"
  | "NOT_FOUND"
  | "RATE_LIMITED"
  | "QUOTA_EXHAUSTED"
  | "UPSTREAM_5XX"
  | "TIMEOUT"
  | "NETWORK_ERROR"
  | "INVALID_RESPONSE"
  | "RESPONSE_TOO_LARGE"
  | "TRANSCRIPT_UNAVAILABLE";

export class SafeProviderError extends Error {
  constructor(
    public readonly providerId: string,
    public readonly safeCode: SafeProviderErrorCode,
    public readonly retryable: boolean,
    public readonly opensCircuit = false,
  ) {
    super(`${providerId}:${safeCode}`);
    this.name = "SafeProviderError";
  }
}

export function classifyProviderHttpStatus(
  providerId: string,
  status: number,
): SafeProviderError {
  if (status === 401 || status === 403) {
    return new SafeProviderError(providerId, "AUTH_REJECTED", false);
  }
  if (status === 404) {
    return new SafeProviderError(providerId, "NOT_FOUND", false);
  }
  if (status === 429) {
    return new SafeProviderError(providerId, "RATE_LIMITED", true, true);
  }
  if (status >= 500 && status <= 599) {
    return new SafeProviderError(providerId, "UPSTREAM_5XX", true, true);
  }
  return new SafeProviderError(providerId, "INVALID_RESPONSE", false);
}

export function toSafeProviderError(
  providerId: string,
  error: unknown,
): SafeProviderError {
  if (error instanceof SafeProviderError) return error;
  if (
    (error instanceof DOMException && error.name === "AbortError") ||
    (error instanceof Error && error.name === "AbortError")
  ) {
    return new SafeProviderError(providerId, "TIMEOUT", true, true);
  }
  return new SafeProviderError(providerId, "NETWORK_ERROR", true, true);
}

