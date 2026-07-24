import { loadBattleStatsBundlePage } from "@/lib/yshelper/publication";
import { allowBattleStatsPublicRequest } from "@/lib/yshelper/rate-limit";
import {
  BattleStatsQueryError,
  invalidQueryResponse,
  parseContentType,
  parseInteger,
  publicRateLimitResponse,
} from "@/lib/yshelper/route-utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function createBattleStatsBundleGet(
  loader = loadBattleStatsBundlePage,
) {
  return async function GET(request: Request) {
    if (!allowBattleStatsPublicRequest(request)) {
      return publicRateLimitResponse();
    }
    try {
      const params = new URL(request.url).searchParams;
      const revisionValue = params.get("revision");
      if (revisionValue === null) throw new BattleStatsQueryError();
      const data = await loader({
        contentType: parseContentType(params.get("type")),
        revision: parseInteger(revisionValue, -1, 1, 2_147_483_647),
        page: parseInteger(params.get("page"), 0, 0, 100_000),
      });
      if (!data) {
        return Response.json(
          {
            ok: false,
            error: {
              code: "not_found",
              message: "公開済み統計が見つかりません。",
            },
          },
          { status: 404, headers: { "Cache-Control": "no-store" } },
        );
      }
      return Response.json(
        { ok: true, data },
        {
          status: 200,
          headers: {
            "Cache-Control": "public, max-age=3600, immutable",
          },
        },
      );
    } catch (error) {
      if (error instanceof BattleStatsQueryError) return invalidQueryResponse();
      throw error;
    }
  };
}

export const GET = createBattleStatsBundleGet();
