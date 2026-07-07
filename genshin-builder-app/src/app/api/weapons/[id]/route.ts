/**
 * 武器詳細取得API
 *
 * GET /api/weapons/:id
 * 詳細画面で武器を切り替えたときに、クライアントから武器性能
 * （基礎攻撃力・サブステータス・武器効果）を取得するために使う。
 * 外部APIへのアクセスはサーバー側で行い、キャッシュを効かせる。
 */

import { NextResponse } from "next/server";
import { fetchWeaponDetail } from "@/lib/api/amber-details";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const detail = await fetchWeaponDetail(id);

  if (!detail) {
    return NextResponse.json(
      { message: "武器情報を取得できませんでした。" },
      { status: 404 },
    );
  }
  return NextResponse.json(detail);
}
