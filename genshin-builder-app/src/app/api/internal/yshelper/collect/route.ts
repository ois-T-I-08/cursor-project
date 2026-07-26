import { NextResponse } from "next/server";

/**
 * HTTP collect is retired. YShelper must be fetched only from the Actions CLI
 * (`npm run yshelper:collect`), never during Next.js request handling.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function createYshelperCollectPost() {
  return async function POST(_request: Request) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "collector_moved",
          message:
            "YShelper収集はGitHub Actions上のCLIへ移行しました。HTTP collectは利用できません。",
        },
      },
      { status: 410, headers: { "Cache-Control": "no-store" } },
    );
  };
}

export const POST = createYshelperCollectPost();
