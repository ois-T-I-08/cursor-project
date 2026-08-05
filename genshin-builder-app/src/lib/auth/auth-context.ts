import "server-only";

import { parseWebSessionCookie } from "./cookies";
import type {
  ResolvedAccountSession,
  WebSessionService,
} from "./web-session-service";
import { webSessionService } from "./web-session-service";

export type UnauthenticatedAuthContext = Readonly<{
  kind: "unauthenticated";
}>;

export type LegacyAnonymousAuthContext = Readonly<{
  kind: "legacyAnonymous";
}>;

export type AccountAuthContext = Readonly<{
  kind: "account";
  accountId: string;
  sessionId: string;
  sessionVersion: number;
  authenticationLevel: "session";
  issuedAt: Date;
  expiresAt: Date;
}>;

export type AuthContext =
  | UnauthenticatedAuthContext
  | LegacyAnonymousAuthContext
  | AccountAuthContext;

const LEGACY_COOKIE_NAME = "gb_user_id";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Cookie headerだけを入力とし、owner/account/session IDをrequest JSON/query/headerから読まない。
 * raw tokenは返却contextへ残さない。
 */
export async function resolveAuthContext(
  cookieHeader: string | null | undefined,
  sessions: WebSessionService = webSessionService,
): Promise<AuthContext> {
  const rawToken = parseWebSessionCookie(cookieHeader);
  if (rawToken) {
    try {
      return accountContext(await sessions.resolveSession(rawToken));
    } catch {
      // Invalid/revoked/expired account Cookie must not expose its reason.
    }
  }
  return hasValidLegacyAnonymousCookie(cookieHeader)
    ? { kind: "legacyAnonymous" }
    : { kind: "unauthenticated" };
}

export function requireAccountAuthContext(
  context: AuthContext,
): AccountAuthContext {
  if (context.kind !== "account") throw new Error("unauthenticated");
  return context;
}

function accountContext(session: ResolvedAccountSession): AccountAuthContext {
  return {
    kind: "account",
    accountId: session.accountId,
    sessionId: session.sessionId,
    sessionVersion: session.sessionVersion,
    authenticationLevel: session.authenticationLevel,
    issuedAt: session.issuedAt,
    expiresAt: session.expiresAt,
  };
}

function hasValidLegacyAnonymousCookie(
  cookieHeader: string | null | undefined,
): boolean {
  if (!cookieHeader || cookieHeader.length > 8_192 || /[\r\n\0]/.test(cookieHeader)) {
    return false;
  }
  let value: string | null = null;
  for (const segment of cookieHeader.split(";")) {
    const separator = segment.indexOf("=");
    if (separator < 1) continue;
    if (segment.slice(0, separator).trim() !== LEGACY_COOKIE_NAME) continue;
    if (value !== null) return false;
    value = segment.slice(separator + 1).trim();
  }
  return value !== null && UUID_PATTERN.test(value);
}
