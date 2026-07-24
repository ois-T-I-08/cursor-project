import { loadBattleStatsManifest } from "@/lib/yshelper/publication";
import { allowBattleStatsPublicRequest } from "@/lib/yshelper/rate-limit";
import { publicRateLimitResponse } from "@/lib/yshelper/route-utils";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Loader = typeof loadBattleStatsManifest;

export function createBattleStatsManifestGet(
  loader: Loader = loadBattleStatsManifest,
) {
  return async function GET(request: Request) {
    if (!allowBattleStatsPublicRequest(request)) {
      return publicRateLimitResponse();
    }
    const { data, etag } = await loader();
    const headers = {
      ETag: etag,
      "Cache-Control": "public, max-age=300, stale-while-revalidate=3600",
    };
    if (etagMatches(request.headers.get("if-none-match"), etag)) {
      return new Response(null, { status: 304, headers });
    }
    return Response.json({ ok: true, data }, { status: 200, headers });
  };
}

export const GET = createBattleStatsManifestGet();

function etagMatches(header: string | null, etag: string): boolean {
  if (!header) return false;
  return header.split(",").some((candidate) => {
    const value = candidate.trim();
    return value === "*" || value === etag || value === `W/${etag}`;
  });
}
