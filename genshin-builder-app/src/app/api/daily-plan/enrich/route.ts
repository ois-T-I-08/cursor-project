import { NextRequest, NextResponse } from "next/server";

import { allowAdminRequest } from "@/lib/admin/rate-limit";
import { enrichDailyPlan } from "@/lib/daily-plan/enrich-daily-plan";
import { parseDailyPlanEnrichRequest } from "@/lib/daily-plan/validation";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_REQUEST_BYTES = 65_536;

export async function POST(request: NextRequest) {
  if (!allowAdminRequest(request, "daily-plan")) {
    return error(429, "rateLimited", "再生成の間隔を空けてください。", {
      "Retry-After": "60",
    });
  }

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

  const data = await enrichDailyPlan(parsed);
  return NextResponse.json(
    { ok: true, data },
    { status: 200, headers: { "Cache-Control": "no-store" } },
  );
}

function error(
  status: number,
  code: string,
  message: string,
  extraHeaders: Record<string, string> = {},
) {
  return NextResponse.json(
    { ok: false, error: { code, message } },
    {
      status,
      headers: { "Cache-Control": "no-store", ...extraHeaders },
    },
  );
}
