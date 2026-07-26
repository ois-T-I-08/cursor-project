import {
  decodeCursor,
  listPublishedCharacters,
} from "@/lib/yshelper/publication";
import { allowBattleStatsPublicRequest } from "@/lib/yshelper/rate-limit";
import {
  BattleStatsQueryError,
  invalidQueryResponse,
  parseContentType,
  parseInteger,
  parseOptionalString,
  publicRateLimitResponse,
} from "@/lib/yshelper/route-utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function createBattleStatsCharactersGet(
  loader = listPublishedCharacters,
) {
  return async function GET(request: Request) {
    if (!allowBattleStatsPublicRequest(request)) {
      return publicRateLimitResponse();
    }
    try {
      const params = new URL(request.url).searchParams;
      const rawCursor = params.get("cursor");
      const cursor = decodeCursor(rawCursor);
      if (rawCursor !== null && cursor === undefined) {
        throw new BattleStatsQueryError();
      }
      const data = await loader({
        contentType: parseContentType(params.get("type")),
        seasonId: parseOptionalString(params.get("seasonId"), "season"),
        side: parseOptionalString(params.get("side"), "scope"),
        limit: parseInteger(params.get("limit"), 50, 1, 100),
        cursor,
      });
      return Response.json(
        { ok: true, data: data ?? { items: [], nextCursor: null } },
        {
          status: 200,
          headers: { "Cache-Control": "public, max-age=300" },
        },
      );
    } catch (error) {
      if (error instanceof BattleStatsQueryError) return invalidQueryResponse();
      throw error;
    }
  };
}

export const GET = createBattleStatsCharactersGet();
