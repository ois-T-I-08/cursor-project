/**
 * マスターデータ同期API
 *
 * POST /api/sync で外部APIからDBへマスターデータを同期する。
 * 将来的に Vercel Cron から定期実行する場合もこのエンドポイントを使う
 * （その際は Authorization ヘッダーによる保護を追加する）。
 */

import { NextResponse } from "next/server";
import { syncMasterData } from "@/lib/sync";

// 同期は数十秒かかることがあるため上限を延長（Vercelのプラン上限に依存）
export const maxDuration = 60;

export async function POST() {
  try {
    const result = await syncMasterData();
    return NextResponse.json({ ok: result.errors.length === 0, ...result });
  } catch (error) {
    console.error("マスターデータ同期に失敗しました:", error);
    return NextResponse.json(
      { ok: false, message: "同期に失敗しました。時間をおいて再度お試しください。" },
      { status: 500 },
    );
  }
}
