import "server-only";

import { isValidOpaqueToken } from "./tokens";

export const WEB_SESSION_COOKIE_NAME = "__Host-gb_session";
const MAX_COOKIE_HEADER_LENGTH = 8_192;

export function parseWebSessionCookie(
  cookieHeader: string | null | undefined,
): string | null {
  if (
    !cookieHeader ||
    cookieHeader.length > MAX_COOKIE_HEADER_LENGTH ||
    /[\r\n\0]/.test(cookieHeader)
  ) {
    return null;
  }

  let found: string | null = null;
  for (const segment of cookieHeader.split(";")) {
    const separator = segment.indexOf("=");
    if (separator < 1) continue;
    const name = segment.slice(0, separator).trim();
    if (name !== WEB_SESSION_COOKIE_NAME) continue;
    if (found !== null) return null;
    const value = segment.slice(separator + 1).trim();
    if (!isValidOpaqueToken(value)) return null;
    found = value;
  }
  return found;
}

export function buildWebSessionCookie(
  token: string,
  expiresAt: Date,
  now = new Date(),
): string {
  if (!isValidOpaqueToken(token) || expiresAt.getTime() <= now.getTime()) {
    throw new TypeError("invalidWebSessionCookie");
  }
  const maxAge = Math.max(
    1,
    Math.floor((expiresAt.getTime() - now.getTime()) / 1_000),
  );
  return [
    `${WEB_SESSION_COOKIE_NAME}=${token}`,
    "Path=/",
    `Max-Age=${maxAge}`,
    `Expires=${expiresAt.toUTCString()}`,
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
  ].join("; ");
}

export function buildWebSessionDeletionCookie(): string {
  return [
    `${WEB_SESSION_COOKIE_NAME}=`,
    "Path=/",
    "Max-Age=0",
    "Expires=Thu, 01 Jan 1970 00:00:00 GMT",
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
  ].join("; ");
}
