import "server-only";

import { prisma } from "@/lib/db";
import { buildManifestHash } from "./cache-key";
import { assertKnownCharacterId } from "./character-match";
import {
  mergeVisualRecommendationsDeterministic,
  mergeVisualRecommendationsWithDeepSeek,
} from "./deepseek-visual-merge";
import { geminiVideoCostHints } from "./gemini-settings";
import {
  permissionStatusSchema,
  publicBuildRecommendationSchema,
  type PublicBuildRecommendation,
} from "./visual-schemas";
import { YoutubeGuideClient, YoutubeError } from "./youtube-client";
import { GUIDE_GAME_DATA_VERSION } from "./versions";

async function audit(action: string, status: string, detail: unknown): Promise<void> {
  await prisma.guideAdminAuditLog.create({
    data: {
      action,
      status,
      detail: JSON.stringify(detail).slice(0, 4_000),
    },
  });
}

function safeJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export async function getGuideAdminOverview() {
  const [channels, videos, jobs, evidences, recommendations, audits] =
    await Promise.all([
      prisma.guideChannel.findMany({ orderBy: { updatedAt: "desc" }, take: 100 }),
      prisma.guideVideo.findMany({
        orderBy: { updatedAt: "desc" },
        take: 200,
        include: { channel: { select: { title: true, permissionStatus: true } } },
      }),
      prisma.guideVisualAnalysisJob.findMany({
        orderBy: { createdAt: "desc" },
        take: 50,
      }),
      prisma.guideVisualEvidence.findMany({
        orderBy: [{ videoId: "asc" }, { startSeconds: "asc" }],
        take: 300,
        include: { visibleTexts: { take: 5 } },
      }),
      prisma.characterBuildRecommendation.findMany({
        orderBy: { updatedAt: "desc" },
        take: 100,
        include: {
          contributions: true,
          revisions: { orderBy: { createdAt: "desc" }, take: 5 },
        },
      }),
      prisma.guideAdminAuditLog.findMany({ orderBy: { createdAt: "desc" }, take: 40 }),
    ]);

  return {
    channels,
    videos,
    jobs,
    evidences,
    recommendations: recommendations.map((row) => ({
      id: row.id,
      characterId: row.characterId,
      status: row.status,
      origin: row.origin,
      overallConfidence: row.overallConfidence,
      notes: row.notes,
      adminNotes: row.adminNotes,
      publishedAt: row.publishedAt,
      lastVerifiedAt: row.lastVerifiedAt,
      updatedAt: row.updatedAt,
      context: safeJson(row.contextPayload, {}),
      mainStats: safeJson(row.mainStatsPayload, []),
      substatPriority: safeJson(row.priorityPayload, []),
      targets: safeJson(row.targetsPayload, []),
      contributions: row.contributions,
      revisions: row.revisions,
    })),
    audits,
    geminiCost: geminiVideoCostHints(),
  };
}

export async function registerGuideChannel(input: {
  channelId: string;
  permissionStatus?: string;
  notes?: string;
  enabled?: boolean;
  attributionRequired?: boolean;
  client?: YoutubeGuideClient;
}) {
  const client = input.client ?? new YoutubeGuideClient();
  const info = await client.fetchChannel(input.channelId);
  const permissionStatus = permissionStatusSchema.parse(
    input.permissionStatus ?? "unknown",
  );
  const row = await prisma.guideChannel.upsert({
    where: { channelId: info.channelId },
    create: {
      channelId: info.channelId,
      title: info.title,
      description: info.description,
      customUrl: info.customUrl,
      thumbnailUrl: info.thumbnailUrl,
      permissionStatus,
      notes: input.notes ?? "",
      enabled: input.enabled ?? true,
      attributionRequired: input.attributionRequired ?? true,
      lastFetchedAt: new Date(),
    },
    update: {
      title: info.title,
      description: info.description,
      customUrl: info.customUrl,
      thumbnailUrl: info.thumbnailUrl,
      permissionStatus,
      notes: input.notes ?? undefined,
      enabled: input.enabled,
      attributionRequired: input.attributionRequired,
      lastFetchedAt: new Date(),
    },
  });
  await audit("registerChannel", "ok", { channelId: row.channelId });
  return { channel: row, uploadsPlaylistId: info.uploadsPlaylistId };
}

export async function updateGuideChannel(input: {
  channelId: string;
  enabled?: boolean;
  permissionStatus?: string;
  notes?: string;
  attributionRequired?: boolean;
}) {
  const data: Record<string, unknown> = {};
  if (input.enabled != null) data.enabled = input.enabled;
  if (input.permissionStatus != null) {
    data.permissionStatus = permissionStatusSchema.parse(input.permissionStatus);
  }
  if (input.notes != null) data.notes = input.notes;
  if (input.attributionRequired != null) {
    data.attributionRequired = input.attributionRequired;
  }
  const row = await prisma.guideChannel.update({
    where: { channelId: input.channelId },
    data,
  });
  if (data.permissionStatus && data.permissionStatus !== "approved_for_processing") {
    await prisma.characterBuildRecommendation.updateMany({
      where: {
        status: "published",
        contributions: { some: { video: { channelId: input.channelId } } },
      },
      data: { status: "approved", publishedAt: null },
    });
  }
  await audit("updateChannel", "ok", { channelId: row.channelId });
  return row;
}

export async function syncChannelVideos(input: {
  channelId: string;
  client?: YoutubeGuideClient;
  maxPages?: number;
}) {
  const channel = await prisma.guideChannel.findUnique({
    where: { channelId: input.channelId },
  });
  if (!channel) throw new Error("channelNotFound");
  if (!channel.enabled) throw new Error("channelDisabled");

  const client = input.client ?? new YoutubeGuideClient();
  const info = await client.fetchChannel(input.channelId);
  const videoIds = await client.listUploadVideoIds(info.uploadsPlaylistId, {
    maxPages: input.maxPages,
  });
  const videos = await client.fetchVideos(videoIds);
  let upserted = 0;
  for (const video of videos) {
    if (video.channelId !== input.channelId) continue;
    const previous = await prisma.guideVideo.findUnique({
      where: { videoId: video.videoId },
    });
    await prisma.guideVideo.upsert({
      where: { videoId: video.videoId },
      create: {
        videoId: video.videoId,
        channelId: video.channelId,
        title: video.title,
        description: video.description,
        publishedAt: video.publishedAt,
        thumbnailUrl: video.thumbnailUrl,
        durationSeconds: video.durationSeconds,
        privacyStatus: video.privacyStatus,
        metadataHash: video.metadataHash,
        sourceUrl: video.sourceUrl,
      },
      update: {
        title: video.title,
        description: video.description,
        publishedAt: video.publishedAt,
        thumbnailUrl: video.thumbnailUrl,
        durationSeconds: video.durationSeconds,
        privacyStatus: video.privacyStatus,
        metadataHash: video.metadataHash,
        sourceUrl: video.sourceUrl,
      },
    });
    if (
      previous &&
      (previous.privacyStatus === "public") &&
      video.privacyStatus !== "public"
    ) {
      await prisma.characterBuildRecommendation.updateMany({
        where: {
          status: "published",
          contributions: { some: { videoId: video.videoId } },
        },
        data: { status: "approved", publishedAt: null },
      });
    }
    upserted += 1;
  }
  await prisma.guideChannel.update({
    where: { channelId: input.channelId },
    data: {
      title: info.title,
      description: info.description,
      thumbnailUrl: info.thumbnailUrl,
      lastFetchedAt: new Date(),
    },
  });
  await audit("syncChannelVideos", "ok", { channelId: input.channelId, upserted });
  return { upserted, totalFetched: videos.length };
}

export async function setVisualEvidenceStatus(input: {
  evidenceId: string;
  approvalStatus: "approved" | "rejected" | "pending_review";
  exclusionCode?: string;
}) {
  const row = await prisma.guideVisualEvidence.update({
    where: { id: input.evidenceId },
    data: {
      approvalStatus: input.approvalStatus,
      exclusionCode: input.exclusionCode ?? "",
    },
  });
  await audit("setVisualEvidenceStatus", "ok", input);
  return row;
}

export async function overrideVisualEvidencePurpose(input: {
  evidenceId: string;
  purposeSummary: string;
}) {
  const row = await prisma.guideVisualEvidence.update({
    where: { id: input.evidenceId },
    data: { purposeSummary: input.purposeSummary.slice(0, 500) },
  });
  await audit("overrideVisualEvidencePurpose", "ok", input);
  return row;
}

export async function setRecommendationStatus(input: {
  recommendationId: string;
  status: "approved" | "rejected" | "published" | "pending_review";
  adminNotes?: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
    include: {
      contributions: { include: { video: { include: { channel: true } }, evidence: true } },
    },
  });
  if (!existing) throw new Error("recommendationNotFound");

  if (input.status === "published") {
    for (const contribution of existing.contributions) {
      if (contribution.video.channel.permissionStatus !== "approved_for_processing") {
        throw new Error("permissionNotApproved");
      }
      if (contribution.video.privacyStatus !== "public") {
        throw new Error("videoNotPublic");
      }
      if (contribution.evidence.approvalStatus === "rejected") {
        throw new Error("rejectedEvidencePresent");
      }
    }
    if (existing.status !== "approved" && existing.status !== "published") {
      throw new Error("notApproved");
    }
  }

  const row = await prisma.characterBuildRecommendation.update({
    where: { id: input.recommendationId },
    data: {
      status: input.status,
      adminNotes: input.adminNotes ?? existing.adminNotes,
      publishedAt: input.status === "published" ? new Date() : existing.publishedAt,
      lastVerifiedAt:
        input.status === "approved" || input.status === "published"
          ? new Date()
          : existing.lastVerifiedAt,
    },
  });

  if (input.status === "published") {
    await prisma.recommendationVisualContribution.updateMany({
      where: {
        recommendationId: row.id,
        decision: { in: ["adopted", "partially_adopted"] },
      },
      data: { usedInPublishedResult: true },
    });
  }
  if (input.status !== "published") {
    await prisma.recommendationVisualContribution.updateMany({
      where: { recommendationId: row.id },
      data: { usedInPublishedResult: false },
    });
  }

  await prisma.guideRecommendationRevision.create({
    data: {
      recommendationId: row.id,
      action: input.status,
      beforePayload: JSON.stringify({ status: existing.status }),
      afterPayload: JSON.stringify({ status: row.status }),
    },
  });
  await audit("setRecommendationStatus", "ok", {
    recommendationId: row.id,
    status: input.status,
  });
  return row;
}

export async function overrideRecommendation(input: {
  recommendationId: string;
  targetsPayload: unknown;
  mainStatsPayload?: unknown;
  priorityPayload?: unknown;
  contextPayload?: unknown;
  adminNotes?: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
  });
  if (!existing) throw new Error("recommendationNotFound");
  const row = await prisma.characterBuildRecommendation.update({
    where: { id: input.recommendationId },
    data: {
      targetsPayload: JSON.stringify(input.targetsPayload),
      mainStatsPayload: JSON.stringify(input.mainStatsPayload ?? safeJson(existing.mainStatsPayload, [])),
      priorityPayload: JSON.stringify(input.priorityPayload ?? safeJson(existing.priorityPayload, [])),
      contextPayload: JSON.stringify(input.contextPayload ?? safeJson(existing.contextPayload, {})),
      adminNotes: input.adminNotes ?? existing.adminNotes,
      status: "pending_review",
      publishedAt: null,
    },
  });
  await prisma.guideRecommendationRevision.create({
    data: {
      recommendationId: row.id,
      action: "override",
      beforePayload: existing.targetsPayload,
      afterPayload: JSON.stringify(input.targetsPayload),
    },
  });
  await audit("overrideRecommendation", "ok", { recommendationId: row.id });
  return row;
}

export async function mergeVisualRecommendations(input: {
  characterId: string;
  evidenceIds: string[];
}) {
  if (!(await assertKnownCharacterId(input.characterId))) {
    throw new Error("unknownCharacterId");
  }
  const evidences = await prisma.guideVisualEvidence.findMany({
    where: {
      id: { in: input.evidenceIds },
      validationStatus: "validated",
      approvalStatus: { in: ["approved", "pending_review"] },
    },
  });
  if (evidences.length === 0) throw new Error("noValidatedEvidence");

  const mergeInput = {
    characterId: input.characterId,
    visualEvidences: evidences.map((evidence) => {
      const payload = safeJson<{
        publishableStatValues?: unknown[];
        recommendedMainStats?: unknown;
        statPriority?: string[];
      }>(evidence.normalizedPayload, {});
      return {
        evidenceId: evidence.id,
        videoId: evidence.videoId,
        startSeconds: evidence.startSeconds,
        endSeconds: evidence.endSeconds,
        evidenceType: evidence.evidenceType,
        visibleTexts: [evidence.exactVisibleText],
        statValues: payload.publishableStatValues ?? [],
        mainStats: payload.recommendedMainStats ?? null,
        statPriority: payload.statPriority ?? [],
        confidence: evidence.confidence,
      };
    }),
    allowedVideoIds: [...new Set(evidences.map((e) => e.videoId))],
    allowedCharacterIds: [input.characterId],
    gameDataVersion: GUIDE_GAME_DATA_VERSION,
  };

  let merged;
  try {
    merged = await mergeVisualRecommendationsWithDeepSeek(mergeInput);
  } catch {
    merged = mergeVisualRecommendationsDeterministic(mergeInput);
  }

  const videoIds = [...new Set(evidences.map((e) => e.videoId))];
  const manifestHash = buildManifestHash(input.characterId, videoIds);
  const manifest = await prisma.guideAnalysisSourceManifest.upsert({
    where: { manifestHash },
    create: {
      characterId: input.characterId,
      videoIdsPayload: JSON.stringify(videoIds),
      manifestHash,
      status: "draft",
      mergePayload: JSON.stringify(merged),
      conflictPayload: "[]",
    },
    update: {
      mergePayload: JSON.stringify(merged),
      status: "draft",
    },
  });

  const recommendation = await prisma.characterBuildRecommendation.create({
    data: {
      characterId: input.characterId,
      status: "pending_review",
      origin: "merged",
      manifestId: manifest.id,
      contextPayload: JSON.stringify(merged.context),
      mainStatsPayload: JSON.stringify(merged.mainStats),
      priorityPayload: JSON.stringify(merged.substatPriority),
      targetsPayload: JSON.stringify(merged.targets),
      overallConfidence: merged.overallConfidence,
      notes: merged.caveats.join("\n"),
    },
  });

  for (const evidence of evidences) {
    await prisma.recommendationVisualContribution.create({
      data: {
        recommendationId: recommendation.id,
        evidenceId: evidence.id,
        videoId: evidence.videoId,
        startSeconds: evidence.startSeconds,
        endSeconds: evidence.endSeconds,
        exactVisibleText: evidence.exactVisibleText.slice(0, 200),
        contributionRole: "primary",
        decision: "adopted",
        decisionSummary: "merged visual evidences",
        usedInPublishedResult: false,
      },
    });
  }
  await audit("mergeVisualRecommendations", "ok", {
    recommendationId: recommendation.id,
    characterId: input.characterId,
  });
  return { recommendationId: recommendation.id, manifestId: manifest.id, merged };
}

export async function getPublishedBuildRecommendation(
  characterId: string,
): Promise<PublicBuildRecommendation | null> {
  const row = await prisma.characterBuildRecommendation.findFirst({
    where: { characterId, status: "published" },
    orderBy: { publishedAt: "desc" },
    include: {
      contributions: {
        where: { usedInPublishedResult: true, decision: { in: ["adopted", "partially_adopted"] } },
        include: { video: { include: { channel: true } } },
      },
    },
  });
  if (!row) return null;

  const targets = (
    safeJson(row.targetsPayload, []) as Array<{
      stat: string;
      recommended?: number;
      min?: number;
      max?: number;
      unit?: "flat" | "percent";
    }>
  ).map((t) => ({
    stat: t.stat,
    recommended: t.recommended,
    min: t.min,
    max: t.max,
    unit: t.unit,
  }));

  const dto = {
    characterId: row.characterId,
    label: "動画内推奨目安" as const,
    status: "published" as const,
    origin: row.origin === "merged" ? ("merged" as const) : ("single_video" as const),
    overallConfidence: row.overallConfidence,
    context: safeJson(row.contextPayload, {}),
    mainStats: safeJson(row.mainStatsPayload, []),
    substatPriority: safeJson(row.priorityPayload, []),
    targets,
    caveats: row.notes
      ? row.notes.split("\n").filter(Boolean)
      : ["条件付き効果・編成バフは含みません。動画画面内で確認した目安です。"],
    lastVerifiedAt: row.lastVerifiedAt?.toISOString() ?? null,
    publishedAt: row.publishedAt?.toISOString() ?? null,
    sources: row.contributions.map((c) => ({
      videoId: c.video.videoId,
      title: c.video.title,
      channelTitle: c.video.channel.title,
      sourceUrl: c.video.sourceUrl,
      publishedAt: c.video.publishedAt?.toISOString() ?? null,
    })),
    evidence: row.contributions.map((c) => ({
      fieldPath: "visual",
      exactVisibleText: c.exactVisibleText.slice(0, 200),
      startSeconds: c.startSeconds,
      endSeconds: c.endSeconds,
      videoId: c.videoId,
    })),
  };

  return publicBuildRecommendationSchema.parse(dto);
}

export async function getPublishedBuildRecommendationSources(characterId: string) {
  const recommendation = await getPublishedBuildRecommendation(characterId);
  if (!recommendation) return null;
  return {
    characterId,
    sources: recommendation.sources,
    evidence: recommendation.evidence,
    lastVerifiedAt: recommendation.lastVerifiedAt,
  };
}

export function mapYoutubeError(error: unknown): string {
  if (error instanceof YoutubeError) return error.code;
  if (error instanceof Error) return error.message;
  return "operationFailed";
}
