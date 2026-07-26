import { NextResponse } from "next/server";
import { getPublishedTemplates } from "@/lib/team-recommendations/replacements/store";

export const runtime = "nodejs";

export async function GET(): Promise<Response> {
  try {
    return NextResponse.json(
      { templates: await getPublishedTemplates() },
      {
        headers: {
          "Cache-Control": "public, s-maxage=300, stale-while-revalidate=86400",
        },
      },
    );
  } catch {
    return NextResponse.json(
      { error: "templatesUnavailable" },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
