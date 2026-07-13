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
import { syncMasterData } from "@/lib/sync";
import { verifySyncApiSecret } from "@/lib/sync-auth";

export const maxDuration = 300;

/** 同期の多重実行を防止するための簡易ロック */
let syncing = false;

export async function POST(request: Request) {
  // ---- 認証 ----
  if (!verifySyncApiSecret(request)) {
    return NextResponse.json(
      { ok: false, message: "認証に失敗しました。" },
      { status: 401 },
    );
  }

  // ---- 多重実行防止 ----
  if (syncing) {
    return NextResponse.json(
      { ok: false, message: "同期は既に実行中です。完了後に再度お試しください。" },
      { status: 409 },
    );
  }

  // ---- 入力検証 ----
  let fullUpgrade = false;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (body.fullUpgrade !== undefined) {
      if (typeof body.fullUpgrade !== "boolean") {
        return NextResponse.json(
          { ok: false, message: "fullUpgrade は真偽値で指定してください。" },
          { status: 400 },
        );
      }
      fullUpgrade = body.fullUpgrade;
    }
  } catch {
    // body なしは差分同期
  }

  // ---- 実行 ----
  syncing = true;
  try {
    const result = await syncMasterData({ fullUpgrade });
    return NextResponse.json({ ok: result.errors.length === 0, ...result });
  } catch (error) {
    console.error("マスターデータ同期に失敗しました:", error);
    return NextResponse.json(
      { ok: false, message: "同期に失敗しました。時間をおいて再度お試しください。" },
      { status: 500 },
    );
  } finally {
    syncing = false;
  }
}
