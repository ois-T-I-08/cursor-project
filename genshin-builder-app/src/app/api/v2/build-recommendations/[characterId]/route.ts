import { NextResponse } from "next/server";
import {
  buildPublicRecommendationEtag,
  matchesPublicRecommendationEtag,
} from "@/lib/build-guides/public-etag";
import { getPublishedBuildRecommendationV2 } from "@/lib/build-guides/public-v2";

export const runtime = "nodejs";

const characterIdPattern = /^[a-z0-9][a-z0-9_-]{0,63}$/i;

export async function GET(
  request: Request,
  context: { params: Promise<{ characterId: string }> },
): Promise<Response> {
  const { characterId } = await context.params;
  if (!characterIdPattern.test(characterId)) {
    return NextResponse.json(
      { ok: false, error: "invalidCharacterId" },
      { status: 400 },
    );
  }
  try {
    const data = await getPublishedBuildRecommendationV2(characterId);
    if (!data) {
      return NextResponse.json(
        { ok: false, error: "notFound" },
        { status: 404, headers: { "Cache-Control": "public, max-age=60" } },
      );
    }
    const etag = buildPublicRecommendationEtag(`v2-${characterId}`, data);
    if (matchesPublicRecommendationEtag(request.headers.get("if-none-match"), etag)) {
      return new Response(null, {
        status: 304,
        headers: {
          ETag: etag,
          "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
        },
      });
    }
    return NextResponse.json(
      { ok: true, data },
      {
        headers: {
          ETag: etag,
          "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
        },
      },
    );
  } catch {
    return NextResponse.json(
      { ok: false, error: "operationFailed" },
      { status: 500 },
    );
  }
}
