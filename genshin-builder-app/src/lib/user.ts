/**
 * 匿名ユーザーID管理
 *
 * Ver.1 ではログイン機能を持たず、ランダムなIDをCookieに保存して
 * ユーザーを識別する。将来Googleログイン等を追加する場合は、
 * この getUserId() の実装を認証セッション参照に差し替えるだけでよい。
 */

import { cookies } from "next/headers";

export const USER_ID_COOKIE = "gb_user_id";

/** Cookieの有効期限（5年） */
export const USER_ID_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 * 5;

/**
 * 現在のユーザーIDをCookieから取得する（未発行なら null）。
 * Server Component / Server Action のどちらからでも呼べる。
 */
export async function getUserId(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get(USER_ID_COOKIE)?.value ?? null;
}

/** 新しい匿名ユーザーIDを生成する */
export function generateUserId(): string {
  return crypto.randomUUID();
}
