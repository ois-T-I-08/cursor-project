import { NextResponse } from "next/server";
import { z } from "zod";
import {
  allowBuildGuideAdminRequest,
  authorizeBuildGuideAdminRequest,
  authorizationHttpStatus,
} from "@/lib/build-guides/admin-auth";
import {
  analyzePendingGenshinVideos,
  analyzeVideoVisuals,
  GuideVisualAnalysisError,
} from "@/lib/build-guides/visual-analysis-service";
import { permissionStatusSchema } from "@/lib/build-guides/visual-schemas";
import {
  getGuideAdminOverview,
  listGuideMasterOptions,
  mapYoutubeError,
  mergeVisualRecommendations,
  overrideRecommendation,
  overrideVisualEvidencePurpose,
  previewRecommendationPublicDto,
  registerGuideChannel,
  restoreRecommendationRevision,
  setRecommendationStatus,
  setVisualEvidenceStatus,
  syncChannelVideos,
  syncPlaylistVideos,
  unpublishRecommendation,
  updateGuideChannel,
  validateStructuredRecommendationDto,
} from "@/lib/build-guides/store";
import { parseYoutubePlaylistId } from "@/lib/build-guides/youtube-client";

export const runtime = "nodejs";
export const maxDuration = 300;

const channelId = z.string().regex(/^UC[\w-]{20,24}$/);
const videoId = z.string().regex(/^[\w-]{11}$/);
const cuid = z.string().regex(/^[a-z0-9_-]{20,40}$/i);
const playlistIdInput = z
  .string()
  .min(10)
  .max(200)
  .refine((value) => parseYoutubePlaylistId(value) != null, {
    message: "invalidPlaylistId",
  });


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
    action: z.literal("syncPlaylistVideos"),
    playlistId: playlistIdInput,
    maxPages: z.number().int().min(1).max(10).optional(),
  }),
  z.strictObject({
    action: z.literal("analyzeVideoVisuals"),
    videoId,
    force: z.boolean().optional(),
    targetCharacterIds: z.array(z.string().max(64)).max(20).optional(),
  }),
  z.strictObject({
    action: z.literal("analyzePendingGenshinVideos"),
    limit: z.number().int().min(1).max(10).optional(),
    mode: z.enum(["newest", "uncoveredCharacters"]).optional(),
    raiseDailyLimitTo: z.number().int().min(1).max(1000).optional(),
  }),
  z.strictObject({
    action: z.literal("reanalyzeVideoVisuals"),
    videoId,
    targetCharacterIds: z.array(z.string().max(64)).max(20).optional(),
    /** When set, clips via Gemini video_metadata (detail FPS). */
    ranges: z.array(rangeSchema).min(1).max(10).optional(),
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
    expectedUpdatedAt: z.string().datetime().optional(),
  }),
  z.strictObject({
    action: z.literal("rejectRecommendation"),
    recommendationId: cuid,
    adminNotes: z.string().max(2_000).optional(),
    expectedUpdatedAt: z.string().datetime().optional(),
  }),
  z.strictObject({
    action: z.literal("publishRecommendation"),
    recommendationId: cuid,
    expectedUpdatedAt: z.string().datetime().optional(),
  }),
  z.strictObject({
    action: z.literal("unpublishRecommendation"),
    recommendationId: cuid,
    expectedUpdatedAt: z.string().datetime().optional(),
  }),
  z.strictObject({
    action: z.literal("overrideRecommendation"),
    recommendationId: cuid,
    targetsPayload: z.unknown(),
    mainStatsPayload: z.unknown().optional(),
    priorityPayload: z.unknown().optional(),
    contextPayload: z.unknown().optional(),
    structuredPayload: z.unknown().optional(),
    adminNotes: z.string().max(2_000).optional(),
    expectedUpdatedAt: z.string().datetime().optional(),
    keepPublished: z.boolean().optional(),
  }),
  z.strictObject({
    action: z.literal("previewRecommendationPublic"),
    recommendationId: cuid,
  }),
  z.strictObject({
    action: z.literal("listGuideMasterOptions"),
  }),
  z.strictObject({
    action: z.literal("restoreRecommendationRevision"),
    recommendationId: cuid,
    revisionId: cuid,
    expectedUpdatedAt: z.string().datetime().optional(),
  }),
  z.strictObject({
    action: z.literal("validateStructuredRecommendation"),
    recommendationId: cuid,
    targetsPayload: z.unknown().optional(),
    mainStatsPayload: z.unknown().optional(),
    structuredPayload: z.unknown().optional(),
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
  if (contentLength > 262_144) {
    return NextResponse.json({ error: "requestTooLarge" }, { status: 413 });
  }
  try {
    const text = await request.text();
    if (Buffer.byteLength(text, "utf8") > 262_144) {
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
      case "syncPlaylistVideos":
        return NextResponse.json(await syncPlaylistVideos(input));
      case "analyzeVideoVisuals":
        return NextResponse.json(
          await analyzeVideoVisuals({
            videoId: input.videoId,
            force: input.force,
            targetCharacterIds: input.targetCharacterIds,
          }),
        );
      case "analyzePendingGenshinVideos":
        return NextResponse.json(
          await analyzePendingGenshinVideos({
            limit: input.limit,
            mode: input.mode,
            raiseDailyLimitTo: input.raiseDailyLimitTo,
          }),
        );
      case "reanalyzeVideoVisuals":
        return NextResponse.json(
          await analyzeVideoVisuals({
            videoId: input.videoId,
            force: true,
            targetCharacterIds: input.targetCharacterIds,
            requestedRanges: input.ranges,
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
            expectedUpdatedAt: input.expectedUpdatedAt,
          }),
        });
      case "rejectRecommendation":
        return NextResponse.json({
          recommendation: await setRecommendationStatus({
            recommendationId: input.recommendationId,
            status: "rejected",
            adminNotes: input.adminNotes,
            expectedUpdatedAt: input.expectedUpdatedAt,
          }),
        });
      case "publishRecommendation":
        return NextResponse.json({
          recommendation: await setRecommendationStatus({
            recommendationId: input.recommendationId,
            status: "published",
            expectedUpdatedAt: input.expectedUpdatedAt,
          }),
        });
      case "unpublishRecommendation":
        return NextResponse.json({
          recommendation: await unpublishRecommendation(
            input.recommendationId,
            input.expectedUpdatedAt,
          ),
        });
      case "overrideRecommendation":
        return NextResponse.json(await overrideRecommendation(input));
      case "previewRecommendationPublic":
        return NextResponse.json(await previewRecommendationPublicDto(input.recommendationId));
      case "listGuideMasterOptions":
        return NextResponse.json(await listGuideMasterOptions());
      case "restoreRecommendationRevision":
        return NextResponse.json(await restoreRecommendationRevision(input));
      case "validateStructuredRecommendation":
        return NextResponse.json(await validateStructuredRecommendationDto(input));
    }
  } catch (error) {
    if (error instanceof z.ZodError || error instanceof SyntaxError) {
      return NextResponse.json({ error: "invalidRequest" }, { status: 400 });
    }
    if (error instanceof GuideVisualAnalysisError) {
      return NextResponse.json({ error: error.code }, { status: 422 });
    }
    if (error instanceof Error) {
      if (error.message === "conflictUpdatedAt") {
        return NextResponse.json({ error: "conflictUpdatedAt" }, { status: 409 });
      }
      if (error.message.startsWith("structuredPublishBlocked:")) {
        return NextResponse.json(
          { error: "structuredPublishBlocked", detail: error.message.slice(25) },
          { status: 422 },
        );
      }
      if (error.message.startsWith("structuredDraftInvalid:")) {
        return NextResponse.json(
          { error: "structuredDraftInvalid", detail: error.message.slice(23) },
          { status: 422 },
        );
      }
    }
    const youtubeCode = mapYoutubeError(error);
    if (
      youtubeCode.startsWith("youtube") ||
      youtubeCode === "channelNotFound" ||
      youtubeCode === "playlistNotFound"
    ) {
      return NextResponse.json({ error: youtubeCode }, { status: 502 });
    }
    if (error instanceof Error && error.message === "invalidPlaylistId") {
      return NextResponse.json({ error: "invalidPlaylistId" }, { status: 400 });
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
