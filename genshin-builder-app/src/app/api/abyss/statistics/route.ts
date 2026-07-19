import { NextResponse } from "next/server";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import { getAbyssStatisticsService } from "@/lib/abyss/statistics-service";
import type { AbyssStatistics } from "@/lib/abyss/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Loader = () => Promise<AbyssStatistics>;

export function createAbyssStatisticsGet(loader: Loader) {
  return async function GET() {
    try {
      const data = await loader();
      return NextResponse.json(
        { ok: true, data },
        {
          status: 200,
          headers: {
            "Cache-Control": data.metadata.isStale
              ? "no-store"
              : "public, max-age=300, stale-while-revalidate=3600",
            "X-Abyss-Data-Stale": String(data.metadata.isStale),
          },
        },
      );
    } catch (error) {
      const safeError = error instanceof AbyssStatisticsError
        ? error
        : new AbyssStatisticsError("unknownError");
      return NextResponse.json(
        {
          ok: false,
          error: {
            code: safeError.code,
            message: userMessage(safeError.code),
          },
        },
        {
          status: statusFor(safeError.code),
          headers: { "Cache-Control": "no-store" },
        },
      );
    }
  };
}

export const GET = createAbyssStatisticsGet(() =>
  getAbyssStatisticsService().load(),
);

function statusFor(code: AbyssStatisticsError["code"]): number {
  switch (code) {
    case "timeout":
      return 504;
    case "invalidResponse":
      return 502;
    case "networkError":
    case "rateLimited":
    case "notConfigured":
    case "featureDisabled":
    case "noData":
      return 503;
    case "unknownError":
      return 500;
  }
}

function userMessage(code: AbyssStatisticsError["code"]): string {
  switch (code) {
    case "notConfigured":
      return "統計APIが設定されていません。";
    case "featureDisabled":
      return "深境螺旋統計は現在利用できません。";
    case "rateLimited":
      return "統計データの取得が混み合っています。";
    case "noData":
      return "表示できる統計データがありません。";
    case "timeout":
    case "networkError":
    case "invalidResponse":
    case "unknownError":
      return "統計データを取得できませんでした。";
  }
}
