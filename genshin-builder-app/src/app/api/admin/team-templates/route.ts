import { NextResponse } from "next/server";
import { z } from "zod";
import {
  authorizeTemplateAdminRequest,
  type AdminAuthorization,
} from "@/lib/team-recommendations/replacements/admin-auth";
import { allowTemplateAdminRequest } from "@/lib/team-recommendations/replacements/admin-rate-limit";
import { generateTemplateReplacements } from "@/lib/team-recommendations/replacements/generation-service";
import { loadLocalCharacterProfiles } from "@/lib/team-recommendations/replacements/profile-source";
import { LocalJsonTeamSource } from "@/lib/team-recommendations/replacements/sources";
import {
  approveImportedTeam,
  getAdminOverview,
  importCharacterProfiles,
  importTeamsFromSource,
  overrideReplacementResult,
  rejectImportedTeam,
  setTemplatePublished,
} from "@/lib/team-recommendations/replacements/store";
import { aiReplacementResultSchema } from "@/lib/team-recommendations/replacements/validation";

export const runtime = "nodejs";
export const maxDuration = 300;

const id = z.string().regex(/^[a-z0-9_-]{20,40}$/i);
const actionSchema = z.discriminatedUnion("action", [
  z.strictObject({ action: z.literal("importLocal") }),
  z.strictObject({ action: z.literal("importProfiles") }),
  z.strictObject({ action: z.literal("approve"), importedTeamId: id }),
  z.strictObject({ action: z.literal("reject"), importedTeamId: id }),
  z.strictObject({ action: z.literal("publish"), templateId: id }),
  z.strictObject({ action: z.literal("unpublish"), templateId: id }),
  z.strictObject({
    action: z.literal("generate"),
    templateId: id,
    force: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("overrideResult"),
    templateId: id,
    replacedCharacterId: z
      .string()
      .regex(/^\d{5,12}(?:-[a-z0-9_-]{1,24})?$/i),
    result: aiReplacementResultSchema,
  }),
]);

export async function GET(request: Request): Promise<Response> {
  const denied = authorize(request);
  if (denied) return denied;
  try {
    return NextResponse.json(await getAdminOverview(), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return safeError(error);
  }
}

export async function POST(request: Request): Promise<Response> {
  const denied = authorize(request);
  if (denied) return denied;
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 65_536) {
    return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
  }
  try {
    const text = await request.text();
    if (Buffer.byteLength(text, "utf8") > 65_536) {
      return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
    }
    const input = actionSchema.parse(JSON.parse(text) as unknown);
    switch (input.action) {
      case "importLocal":
        return NextResponse.json({
          summary: await importTeamsFromSource(new LocalJsonTeamSource()),
        });
      case "importProfiles":
        return NextResponse.json({
          summary: await importCharacterProfiles(await loadLocalCharacterProfiles()),
        });
      case "approve":
        return NextResponse.json({
          templateId: await approveImportedTeam(input.importedTeamId),
        });
      case "reject":
        await rejectImportedTeam(input.importedTeamId);
        return NextResponse.json({ ok: true });
      case "publish":
        await setTemplatePublished(input.templateId, true);
        return NextResponse.json({ ok: true });
      case "unpublish":
        await setTemplatePublished(input.templateId, false);
        return NextResponse.json({ ok: true });
      case "generate":
        return NextResponse.json({
          summary: await generateTemplateReplacements(input.templateId, {
            force: input.force,
          }),
        });
      case "overrideResult":
        return NextResponse.json({
          result: await overrideReplacementResult({
            templateId: input.templateId,
            replacedCharacterId: input.replacedCharacterId,
            result: input.result,
          }),
        });
    }
  } catch (error) {
    if (error instanceof z.ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
    }
    return safeError(error);
  }
}

function authorize(request: Request): Response | null {
  const authorization = authorizeTemplateAdminRequest(request);
  if (authorization !== "authorized") {
    return NextResponse.json(
      { error: authorization },
      { status: authorizationStatus(authorization) },
    );
  }
  if (!allowTemplateAdminRequest(request)) {
    return NextResponse.json(
      { error: "rateLimited" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }
  return null;
}

function authorizationStatus(value: AdminAuthorization): number {
  if (value === "forbidden") return 403;
  if (value === "unavailable") return 503;
  return 401;
}

function safeError(error: unknown): Response {
  const code =
    error instanceof Error && /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message)
      ? error.message
      : "operationFailed";
  const notFound = code.endsWith("NotFound");
  return NextResponse.json(
    { error: code },
    { status: notFound ? 404 : code.includes("Incomplete") ? 409 : 500 },
  );
}
