import { NextResponse } from "next/server";
import { z } from "zod";
import { analyzeVideoTranscript, GuideAnalysisError } from "@/lib/build-guides/analysis-service";
import {
  allowBuildGuideAdminRequest,
  authorizeBuildGuideAdminRequest,
  authorizationHttpStatus,
} from "@/lib/build-guides/admin-auth";
import { validatedGuidePayloadSchema, permissionStatusSchema } from "@/lib/build-guides/schemas";
import {
  deleteTranscriptArtifacts,
  getGuideAdminOverview,
  mapYoutubeError,
  mergeVideoRecommendations,
  overrideRecommendation,
  registerGuideChannel,
  setContributionInclusion,
  setRecommendationStatus,
  syncChannelVideos,
  updateGuideChannel,
} from "@/lib/build-guides/store";
import { prisma } from "@/lib/db";

export const runtime = "nodejs";
export const maxDuration = 300;

const channelId = z.string().regex(/^UC[\w-]{20,24}$/);
const videoId = z.string().regex(/^[\w-]{11}$/);
const cuid = z.string().regex(/^[a-z0-9_-]{20,40}$/i);

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
    action: z.literal("analyzeTranscript"),
    videoId,
    transcript: z.string().min(1).max(2_000_000),
    format: z.enum(["txt", "vtt", "srt"]).optional(),
    force: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("analyzeDescription"),
    videoId,
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
    payload: validatedGuidePayloadSchema,
    adminNotes: z.string().max(2_000).optional(),
  }),
  z.strictObject({
    action: z.literal("mergeRecommendations"),
    characterId: z.string().min(1).max(64),
    videoIds: z.array(videoId).min(2).max(10),
  }),
  z.strictObject({
    action: z.literal("setContributionInclusion"),
    contributionId: cuid,
    inclusion: z.enum(["included", "excluded"]),
    reason: z.string().max(500).optional(),
  }),
  z.strictObject({
    action: z.literal("reanalyze"),
    videoId,
    transcript: z.string().min(1).max(2_000_000),
    format: z.enum(["txt", "vtt", "srt"]).optional(),
  }),
  z.strictObject({
    action: z.literal("deleteTranscriptData"),
    videoId,
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
  if (contentLength > 2_100_000) {
    return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
  }
  try {
    const text = await request.text();
    if (Buffer.byteLength(text, "utf8") > 2_100_000) {
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
      case "analyzeDescription": {
        const video = await prisma.guideVideo.findUnique({ where: { videoId: input.videoId } });
        if (!video) {
          return NextResponse.json({ error: "videoNotFound" }, { status: 404 });
        }
        return NextResponse.json({
          videoId: video.videoId,
          title: video.title,
          description: video.description.slice(0, 4_000),
        });
      }
      case "analyzeTranscript":
      case "reanalyze": {
        const video = await prisma.guideVideo.findUnique({ where: { videoId: input.videoId } });
        if (!video) {
          return NextResponse.json({ error: "videoNotFound" }, { status: 404 });
        }
        const result = await analyzeVideoTranscript({
          videoId: video.videoId,
          title: video.title,
          description: video.description,
          transcriptRaw: input.transcript,
          format: input.format,
          force: input.action === "reanalyze" || input.force,
        });
        return NextResponse.json(result);
      }
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
        return NextResponse.json({ recommendation: row });
      }
      case "overrideRecommendation":
        return NextResponse.json({
          recommendation: await overrideRecommendation(input),
        });
      case "mergeRecommendations":
        return NextResponse.json(await mergeVideoRecommendations(input));
      case "setContributionInclusion":
        return NextResponse.json({
          contribution: await setContributionInclusion(input),
        });
      case "deleteTranscriptData":
        return NextResponse.json(await deleteTranscriptArtifacts(input.videoId));
    }
  } catch (error) {
    if (error instanceof z.ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
    }
    if (error instanceof GuideAnalysisError) {
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
