import "server-only";

import { timingSafeEqual } from "node:crypto";

export type AdminAuthorization =
  | "authorized"
  | "missing"
  | "forbidden"
  | "unavailable";

/**
 * Fail-closed Bearer auth against an env secret name.
 * Missing/empty secret → unavailable (503).
 */
export function authorizeBearerSecret(
  request: Request,
  secretEnvName: string,
): AdminAuthorization {
  const secret = process.env[secretEnvName]?.trim();
  if (!secret) return "unavailable";
  const header = request.headers.get("authorization");
  if (
    !header ||
    !header.startsWith("Bearer ") ||
    header.includes(",") ||
    header.length <= 7
  ) {
    return "missing";
  }
  const token = header.slice(7);
  if (token.trim() !== token || /\s/.test(token)) return "missing";
  const expected = Buffer.from(secret);
  const actual = Buffer.from(token);
  return expected.length === actual.length && timingSafeEqual(expected, actual)
    ? "authorized"
    : "forbidden";
}

export function authorizationHttpStatus(value: AdminAuthorization): number {
  if (value === "forbidden") return 403;
  if (value === "unavailable") return 503;
  return 401;
}
