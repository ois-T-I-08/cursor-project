import { NextRequest, NextResponse } from "next/server";

import { enrichDailyPlan } from "@/lib/daily-plan/enrich-daily-plan";
import { parseDailyPlanEnrichRequest } from "@/lib/daily-plan/validation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_REQUEST_BYTES = 32_768;

export async function POST(request: NextRequest) {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(length) && length > MAX_REQUEST_BYTES) {
    return error(413, "invalidRequest", "送信データが大きすぎます。");
  }

  let parsed;
  try {
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > MAX_REQUEST_BYTES) {
      return error(413, "invalidRequest", "送信データが大きすぎます。");
    }
    parsed = parseDailyPlanEnrichRequest(JSON.parse(raw) as unknown);
  } catch {
    return error(400, "invalidRequest", "今日やることの入力を確認できませんでした。");
  }

  try {
    const data = await enrichDailyPlan(parsed);
    return NextResponse.json(
      { ok: true, data },
      { status: 200, headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return error(503, "temporarilyUnavailable", "今日やることの補強を一時的に利用できません。");
  }
}

function error(status: number, code: string, message: string) {
  return NextResponse.json(
    { ok: false, error: { code, message } },
    { status, headers: { "Cache-Control": "no-store" } },
  );
}
