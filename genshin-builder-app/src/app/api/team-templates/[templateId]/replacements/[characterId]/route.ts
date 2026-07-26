import { NextResponse } from "next/server";
import { getPublishedReplacement } from "@/lib/team-recommendations/replacements/store";

export const runtime = "nodejs";

const idPattern = /^[a-z0-9_-]{5,40}$/i;

export async function GET(
  _request: Request,
  context: { params: Promise<{ templateId: string; characterId: string }> },
): Promise<Response> {
  const { templateId, characterId } = await context.params;
  if (!idPattern.test(templateId) || !/^\d{5,12}(?:-[a-z0-9_-]{1,24})?$/i.test(characterId)) {
    return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
  }
  try {
    const result = await getPublishedReplacement({
      templateId,
      replacedCharacterId: characterId.toLowerCase(),
    });
    if (!result) {
      return NextResponse.json({ error: "replacementNotFound" }, { status: 404 });
    }
    return NextResponse.json(result, {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=86400",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "replacementUnavailable" },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
