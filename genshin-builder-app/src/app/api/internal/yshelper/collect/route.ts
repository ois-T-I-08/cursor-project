import { NextResponse } from "next/server";

import {
  authorizeYshelperCollector,
  BattleStatsCollectorAlreadyRunningError,
  runBattleStatsCollectorExclusive,
  type BattleStatsCollectResult,
} from "@/lib/yshelper/collector";
import { YshelperAdapterNotConfiguredError } from "@/lib/yshelper/adapter";
import { YshelperClientConfigurationError } from "@/lib/yshelper/client";
import {
  allowSyncRequest,
  syncRateLimitKey,
} from "@/lib/sync-rate-limit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

type Runner = () => Promise<BattleStatsCollectResult>;

export function createYshelperCollectPost(
  runner: Runner = runBattleStatsCollectorExclusive,
) {
  return async function POST(request: Request) {
    if (!authorizeYshelperCollector(request)) {
      return NextResponse.json(
        {
          ok: false,
          error: { code: "unauthorized", message: "認証に失敗しました。" },
        },
        { status: 401, headers: { "Cache-Control": "no-store" } },
      );
    }
    if (
      !allowSyncRequest(`yshelper:${syncRateLimitKey(request)}`)
    ) {
      return NextResponse.json(
        {
          ok: false,
          error: {
            code: "rate_limited",
            message: "同期要求が多すぎます。",
          },
        },
        { status: 429, headers: { "Cache-Control": "no-store" } },
      );
    }
    try {
      const result = await runner();
      return NextResponse.json(
        { ok: result.status === "success" || result.status === "skipped", ...result },
        {
          status: result.status === "failed" ? 502 : result.status === "invalid" ? 422 : 200,
          headers: { "Cache-Control": "no-store" },
        },
      );
    } catch (error) {
      if (error instanceof BattleStatsCollectorAlreadyRunningError) {
        return NextResponse.json(
          {
            ok: false,
            error: {
              code: "already_running",
              message: "統計同期は既に実行中です。",
            },
          },
          { status: 409, headers: { "Cache-Control": "no-store" } },
        );
      }
      if (
        error instanceof YshelperAdapterNotConfiguredError ||
        error instanceof YshelperClientConfigurationError
      ) {
        return NextResponse.json(
          {
            ok: false,
            error: {
              code: "not_configured",
              message: "YShelper統計同期は未設定です。",
            },
          },
          { status: 503, headers: { "Cache-Control": "no-store" } },
        );
      }
      console.error("battle_statistics", {
        event: "collector_route_failed",
        cacheState: "unchanged",
        fallbackUsed: true,
      });
      return NextResponse.json(
        {
          ok: false,
          error: {
            code: "collector_failed",
            message: "統計同期に失敗しました。",
          },
        },
        { status: 500, headers: { "Cache-Control": "no-store" } },
      );
    }
  };
}

export const POST = createYshelperCollectPost();
