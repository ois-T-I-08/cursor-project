import "server-only";

import { createHash, randomBytes } from "node:crypto";
import { AccountSessionError } from "./errors";

export const OPAQUE_TOKEN_BYTES = 32;
export const OPAQUE_TOKEN_LENGTH = 43;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/** 256-bitの暗号学的乱数。raw値は呼出元へ一度だけ返す。 */
export function generateOpaqueToken(): string {
  return randomBytes(OPAQUE_TOKEN_BYTES).toString("base64url");
}

export function isValidOpaqueToken(value: unknown): value is string {
  return typeof value === "string" && TOKEN_PATTERN.test(value);
}

/**
 * Secret追加禁止のfoundation段階ではSHA-256を使用する。
 * 入力tokenは256-bit randomであり、DBにはこのhex digestだけを保存する。
 */
export function hashOpaqueToken(token: string): string {
  if (!isValidOpaqueToken(token)) {
    throw new AccountSessionError("invalidSession");
  }
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** ログ・audit向けの非可逆な短縮相関値。元IDは返さない。 */
export function correlationValue(value: string): string {
  return createHash("sha256")
    .update("gb-auth-correlation-v1\0", "utf8")
    .update(value, "utf8")
    .digest("hex")
    .slice(0, 12);
}
