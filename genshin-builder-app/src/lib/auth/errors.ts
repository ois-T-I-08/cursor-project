import "server-only";

export const ACCOUNT_SESSION_ERROR_CODES = [
  "featureDisabled",
  "invalidSession",
  "sessionExpired",
  "sessionRevoked",
  "accountDisabled",
  "rotationConflict",
  "retryExhausted",
  "clientOwnershipForbidden",
  "temporarilyUnavailable",
] as const;

export type AccountSessionErrorCode =
  (typeof ACCOUNT_SESSION_ERROR_CODES)[number];

const KNOWN_CODES = new Set<string>(ACCOUNT_SESSION_ERROR_CODES);

export class AccountSessionError extends Error {
  readonly retryable: boolean;

  constructor(
    readonly code: AccountSessionErrorCode,
    options: { retryable?: boolean; cause?: unknown } = {},
  ) {
    super(code, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = "AccountSessionError";
    this.retryable = options.retryable ?? false;
  }
}

export function safeAccountSessionErrorCode(
  error: unknown,
): AccountSessionErrorCode {
  if (
    error instanceof AccountSessionError ||
    (typeof error === "object" && error !== null && "code" in error)
  ) {
    const code = String((error as { code: unknown }).code);
    if (KNOWN_CODES.has(code)) return code as AccountSessionErrorCode;
  }
  return "temporarilyUnavailable";
}
