import "server-only";

import { timingSafeEqual } from "node:crypto";

export type AdminAuthorization =
  | "authorized"
  | "missing"
  | "forbidden"
  | "unavailable";

export function authorizeTemplateAdminRequest(request: Request): AdminAuthorization {
  const secret = process.env.TEAM_TEMPLATE_ADMIN_SECRET?.trim();
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
