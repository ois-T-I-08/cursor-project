/**
 * マスターデータ同期API（Cron / 外部トリガー専用）
 *
 * POST /api/sync で外部APIからDBへマスターデータを同期する。
 * Body: { "fullUpgrade": false } — false=差分（既定）, true=突破データ全件再取得
 *
 * 設定画面の手動同期は Server Action（syncMasterDataAction）を使用すること。
 * Authorization: Bearer <SYNC_API_SECRET> が必要（本番必須）。
 *
 * 多重実行防止: 同一プロセス内で同期実行中は 409 Conflict を返す。
 *   Vercel のサーバーレス環境ではインスタンス間の排他は保証されないが、
 *   同一インスタンス内での競合は防止される。
 */

import { NextResponse } from "next/server";
import { authorizeSyncRequest } from "@/lib/sync-auth";
import {
  runSyncExclusive,
  SyncAlreadyRunningError,
} from "@/lib/sync-execution";
import {
  parseSyncRequest,
  SyncRequestError,
} from "@/lib/sync-request";
import {
  allowSyncRequest,
  syncRateLimitKey,
} from "@/lib/sync-rate-limit";

export const maxDuration = 300;

export async function POST(request: Request) {
  // ---- 認証 ----
  const authorization = authorizeSyncRequest(request);
  if (authorization !== "authorized") {
    return NextResponse.json(
      { ok: false, message: "認証に失敗しました。" },
      { status: authorization === "forbidden" ? 403 : 401 },
    );
  }
  if (!allowSyncRequest(syncRateLimitKey(request))) {
    return NextResponse.json(
      { ok: false, message: "同期要求が多すぎます。時間をおいて再試行してください。" },
      { status: 429 },
    );
  }

  // ---- 入力検証 ----
  let fullUpgrade: boolean;
  try {
    ({ fullUpgrade } = await parseSyncRequest(request));
  } catch (error) {
    if (error instanceof SyncRequestError) {
      return NextResponse.json(
        {
          ok: false,
          message:
            error.status === 413
              ? "リクエストが大きすぎます。"
              : "リクエスト形式が不正です。",
        },
        { status: error.status },
      );
    }
    throw error;
  }

  // ---- 実行 ----
  try {
    const result = await runSyncExclusive(fullUpgrade);
    const { errors, ...safeResult } = result;
    return NextResponse.json(
      {
        ok: errors.length === 0,
        ...safeResult,
        errorCount: errors.length,
      },
      { status: errors.length === 0 ? 200 : 502 },
    );
  } catch (error) {
    if (error instanceof SyncAlreadyRunningError) {
      return NextResponse.json(
        { ok: false, message: "同期は既に実行中です。完了後に再度お試しください。" },
        { status: 409 },
      );
    }
    console.error("マスターデータ同期に失敗しました。");
    return NextResponse.json(
      { ok: false, message: "同期に失敗しました。時間をおいて再度お試しください。" },
      { status: 500 },
    );
  }
}
