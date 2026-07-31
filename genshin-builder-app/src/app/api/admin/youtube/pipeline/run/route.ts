import { NextResponse } from "next/server";
import { z } from "zod";
import {
  allowBuildGuideAdminRequest,
  authorizeBuildGuideAdminRequest,
  authorizationHttpStatus,
} from "@/lib/build-guides/admin-auth";
import { runDefaultYoutubeGuidePipeline } from "@/lib/build-guides/automation/pipeline-entry";

export const runtime = "nodejs";
export const maxDuration = 300;

const requestSchema = z.strictObject({
  pipelineRunId: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{5,100}$/),
  trigger: z.enum(["schedule", "workflow_dispatch", "admin"]),
  dryRun: z.boolean().default(true),
});

export async function POST(request: Request): Promise<Response> {
  const authorization = authorizeBuildGuideAdminRequest(request);
  if (authorization !== "authorized") {
    return NextResponse.json(
      { error: authorization },
      { status: authorizationHttpStatus(authorization) },
    );
  }
  if (!allowBuildGuideAdminRequest(request)) {
    return NextResponse.json(
      { error: "rateLimited" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 16_384) {
    return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
  }
  try {
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > 16_384) {
      return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
    }
    const input = requestSchema.parse(JSON.parse(raw) as unknown);
    const summary = await runDefaultYoutubeGuidePipeline(input);
    return NextResponse.json(
      { ok: true, summary },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    if (error instanceof z.ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
    }
    return NextResponse.json(
      { error: "operationFailed" },
      { status: 500 },
    );
  }
}
