import { timingSafeEqual } from "node:crypto";

/**
 * マスタ同期 API（POST /api/sync）の認証
 *
 * - 設定画面の Server Action と外部トリガーの両方を同じ秘密で保護
 * - 同一オリジン/CORSだけを認可根拠にはしない
 */

/** POST /api/sync のリクエストが認可されているか */
export function verifySyncApiSecret(request: Request): boolean {
  return authorizeSyncRequest(request) === "authorized";
}

export type SyncAuthorization =
  | "authorized"
  | "missing"
  | "forbidden"
  | "unavailable";

export function authorizeSyncRequest(request: Request): SyncAuthorization {
  const auth = request.headers.get("authorization");
  if (
    auth === null ||
    !auth.startsWith("Bearer ") ||
    auth.includes(",") ||
    auth.length <= "Bearer ".length
  ) {
    return "missing";
  }

  const token = auth.slice("Bearer ".length);
  if (token.trim() !== token || /\s/.test(token)) {
    return "missing";
  }
  return authorizeSyncSecret(token);
}

/** Server Action callers must provide the same secret as the Cron API. */
export function verifySyncActionSecret(token: string | undefined): boolean {
  return authorizeSyncSecret(token) === "authorized";
}

function authorizeSyncSecret(token: string | undefined): SyncAuthorization {
  const secret = process.env.SYNC_API_SECRET;

  if (!secret) {
    return process.env.NODE_ENV === "production"
      ? "unavailable"
      : "authorized";
  }

  if (!token) return "missing";
  const expected = Buffer.from(secret);
  const actual = Buffer.from(token);
  const matches =
    expected.length === actual.length && timingSafeEqual(expected, actual)
  return matches ? "authorized" : "forbidden";
}
