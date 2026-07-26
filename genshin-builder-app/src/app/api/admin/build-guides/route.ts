import { NextResponse } from "next/server";
import { z } from "zod";
import {
  allowBuildGuideAdminRequest,
  authorizeBuildGuideAdminRequest,
  authorizationHttpStatus,
} from "@/lib/build-guides/admin-auth";
import {
  analyzeVideoVisuals,
  GuideVisualAnalysisError,
} from "@/lib/build-guides/visual-analysis-service";
import { permissionStatusSchema } from "@/lib/build-guides/visual-schemas";
import {
  getGuideAdminOverview,
  mapYoutubeError,
  mergeVisualRecommendations,
  overrideRecommendation,
  overrideVisualEvidencePurpose,
  registerGuideChannel,
  setRecommendationStatus,
  setVisualEvidenceStatus,
  syncChannelVideos,
  updateGuideChannel,
} from "@/lib/build-guides/store";
import { prisma } from "@/lib/db";

export const runtime = "nodejs";
export const maxDuration = 300;

const channelId = z.string().regex(/^UC[\w-]{20,24}$/);
const videoId = z.string().regex(/^[\w-]{11}$/);
const cuid = z.string().regex(/^[a-z0-9_-]{20,40}$/i);

const rangeSchema = z.strictObject({
  startSeconds: z.number().nonnegative(),
  endSeconds: z.number().nonnegative(),
  reason: z.string().max(200),
});

const actionSchema = z.discriminatedUnion("action", [
  z.strictObject({
    action: z.literal("registerChannel"),
    channelId,
    permissionStatus: permissionStatusSchema.optional(),
    notes: z.string().max(2_000).optional(),
    enabled: z.boolean().optional(),
    attributionRequired: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("updateChannel"),
    channelId,
    permissionStatus: permissionStatusSchema.optional(),
    notes: z.string().max(2_000).optional(),
    enabled: z.boolean().optional(),
    attributionRequired: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("syncChannelVideos"),
    channelId,
    maxPages: z.number().int().min(1).max(10).optional(),
  }),
  z.strictObject({
    action: z.literal("analyzeVideoVisuals"),
    videoId,
    force: z.boolean().optional(),
    targetCharacterIds: z.array(z.string().max(64)).max(20).optional(),
  }),
  z.strictObject({
    action: z.literal("reanalyzeVideoVisuals"),
    videoId,
    targetCharacterIds: z.array(z.string().max(64)).max(20).optional(),
  }),
  z.strictObject({
    action: z.literal("analyzeSelectedRanges"),
    videoId,
    ranges: z.array(rangeSchema).min(1).max(10),
    force: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("approveVisualEvidence"),
    evidenceId: cuid,
  }),
  z.strictObject({
    action: z.literal("rejectVisualEvidence"),
    evidenceId: cuid,
    exclusionCode: z.string().max(100).optional(),
  }),
  z.strictObject({
    action: z.literal("overrideVisualEvidencePurpose"),
    evidenceId: cuid,
    purposeSummary: z.string().max(500),
  }),
  z.strictObject({
    action: z.literal("mergeVisualRecommendations"),
    characterId: z.string().min(1).max(64),
    evidenceIds: z.array(cuid).min(1).max(40),
  }),
  z.strictObject({
    action: z.literal("approveRecommendation"),
    recommendationId: cuid,
    adminNotes: z.string().max(2_000).optional(),
  }),
  z.strictObject({
    action: z.literal("rejectRecommendation"),
    recommendationId: cuid,
    adminNotes: z.string().max(2_000).optional(),
  }),
  z.strictObject({
    action: z.literal("publishRecommendation"),
    recommendationId: cuid,
  }),
  z.strictObject({
    action: z.literal("unpublishRecommendation"),
    recommendationId: cuid,
  }),
  z.strictObject({
    action: z.literal("overrideRecommendation"),
    recommendationId: cuid,
    targetsPayload: z.unknown(),
    mainStatsPayload: z.unknown().optional(),
    priorityPayload: z.unknown().optional(),
    contextPayload: z.unknown().optional(),
    adminNotes: z.string().max(2_000).optional(),
  }),
]);

export async function GET(request: Request): Promise<Response> {
  const denied = authorize(request);
  if (denied) return denied;
  try {
    return NextResponse.json(await getGuideAdminOverview(), {
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
      case "registerChannel":
        return NextResponse.json(await registerGuideChannel(input));
      case "updateChannel":
        return NextResponse.json({ channel: await updateGuideChannel(input) });
      case "syncChannelVideos":
        return NextResponse.json(await syncChannelVideos(input));
      case "analyzeVideoVisuals":
        return NextResponse.json(
          await analyzeVideoVisuals({
            videoId: input.videoId,
            force: input.force,
            targetCharacterIds: input.targetCharacterIds,
          }),
        );
      case "reanalyzeVideoVisuals":
        return NextResponse.json(
          await analyzeVideoVisuals({
            videoId: input.videoId,
            force: true,
            targetCharacterIds: input.targetCharacterIds,
          }),
        );
      case "analyzeSelectedRanges":
        return NextResponse.json(
          await analyzeVideoVisuals({
            videoId: input.videoId,
            force: input.force ?? true,
            requestedRanges: input.ranges,
          }),
        );
      case "approveVisualEvidence":
        return NextResponse.json({
          evidence: await setVisualEvidenceStatus({
            evidenceId: input.evidenceId,
            approvalStatus: "approved",
          }),
        });
      case "rejectVisualEvidence":
        return NextResponse.json({
          evidence: await setVisualEvidenceStatus({
            evidenceId: input.evidenceId,
            approvalStatus: "rejected",
            exclusionCode: input.exclusionCode ?? "adminRejected",
          }),
        });
      case "overrideVisualEvidencePurpose":
        return NextResponse.json({
          evidence: await overrideVisualEvidencePurpose(input),
        });
      case "mergeVisualRecommendations":
        return NextResponse.json(await mergeVisualRecommendations(input));
      case "approveRecommendation":
        return NextResponse.json({
          recommendation: await setRecommendationStatus({
            recommendationId: input.recommendationId,
            status: "approved",
            adminNotes: input.adminNotes,
          }),
        });
      case "rejectRecommendation":
        return NextResponse.json({
          recommendation: await setRecommendationStatus({
            recommendationId: input.recommendationId,
            status: "rejected",
            adminNotes: input.adminNotes,
          }),
        });
      case "publishRecommendation":
        return NextResponse.json({
          recommendation: await setRecommendationStatus({
            recommendationId: input.recommendationId,
            status: "published",
          }),
        });
      case "unpublishRecommendation": {
        const existing = await prisma.characterBuildRecommendation.findUnique({
          where: { id: input.recommendationId },
        });
        if (!existing) {
          return NextResponse.json({ error: "recommendationNotFound" }, { status: 404 });
        }
        const row = await prisma.characterBuildRecommendation.update({
          where: { id: input.recommendationId },
          data: { status: "approved", publishedAt: null },
        });
        await prisma.recommendationVisualContribution.updateMany({
          where: { recommendationId: row.id },
          data: { usedInPublishedResult: false },
        });
        return NextResponse.json({ recommendation: row });
      }
      case "overrideRecommendation":
        return NextResponse.json({
          recommendation: await overrideRecommendation(input),
        });
    }
  } catch (error) {
    if (error instanceof z.ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
    }
    if (error instanceof GuideVisualAnalysisError) {
      return NextResponse.json({ error: error.code }, { status: 422 });
    }
    const youtubeCode = mapYoutubeError(error);
    if (youtubeCode.startsWith("youtube") || youtubeCode === "channelNotFound") {
      return NextResponse.json({ error: youtubeCode }, { status: 502 });
    }
    return safeError(error);
  }
}

function authorize(request: Request): Response | null {
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
  return null;
}

function safeError(error: unknown): Response {
  const code =
    error instanceof Error && /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message)
      ? error.message
      : "operationFailed";
  const notFound = code.endsWith("NotFound");
  return NextResponse.json(
    { error: code },
    {
      status: notFound
        ? 404
        : code === "permissionNotApproved" || code === "notApproved"
          ? 409
          : 500,
    },
  );
}
