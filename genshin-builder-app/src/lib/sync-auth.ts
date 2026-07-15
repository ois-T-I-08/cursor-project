import { timingSafeEqual } from "node:crypto";

/**
 * マスタ同期 API（POST /api/sync）の認証
 *
 * - 設定画面の Server Action と外部トリガーの両方を同じ秘密で保護
 * - 同一オリジン/CORSだけを認可根拠にはしない
 */

/** POST /api/sync のリクエストが認可されているか */
export function verifySyncApiSecret(request: Request): boolean {
  const auth = request.headers.get("authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : undefined;
  return verifySyncSecret(token);
}

/** Server Action callers must provide the same secret as the Cron API. */
export function verifySyncActionSecret(token: string | undefined): boolean {
  return verifySyncSecret(token);
}

function verifySyncSecret(token: string | undefined): boolean {
  const secret = process.env.SYNC_API_SECRET;

  if (!secret) {
    // Fail closed in production. Local development remains convenient.
    return process.env.NODE_ENV !== "production";
  }

  if (!token) return false;
  const expected = Buffer.from(secret);
  const actual = Buffer.from(token);
  return (
    expected.length === actual.length && timingSafeEqual(expected, actual)
  );
}
