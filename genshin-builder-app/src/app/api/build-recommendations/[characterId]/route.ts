import { NextResponse } from "next/server";
import { getPublishedBuildRecommendation } from "@/lib/build-guides/store";

export const runtime = "nodejs";

const characterIdPattern = /^[a-z0-9][a-z0-9_-]{0,63}$/i;

export async function GET(
  _request: Request,
  context: { params: Promise<{ characterId: string }> },
): Promise<Response> {
  const { characterId } = await context.params;
  if (!characterIdPattern.test(characterId)) {
    return NextResponse.json({ ok: false, error: "invalidCharacterId" }, { status: 400 });
  }
  try {
    const data = await getPublishedBuildRecommendation(characterId);
    if (!data) {
      return NextResponse.json(
        { ok: false, error: "notFound" },
        { status: 404, headers: { "Cache-Control": "public, max-age=60" } },
      );
    }
    // Never expose raw AI / admin notes / internal hashes
    return NextResponse.json(
      { ok: true, data },
      { headers: { "Cache-Control": "public, max-age=300" } },
    );
  } catch {
    return NextResponse.json({ ok: false, error: "operationFailed" }, { status: 500 });
  }
}
