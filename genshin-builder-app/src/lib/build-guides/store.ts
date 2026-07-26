import "server-only";

import { createHash } from "node:crypto";
import { prisma } from "@/lib/db";
import { YoutubeGuideClient, YoutubeError } from "./youtube-client";
import { mergeGuidePayloads } from "./merge-service";
import { buildManifestHash } from "./cache-key";
import {
  publicBuildRecommendationSchema,
  type PublicBuildRecommendation,
  type ValidatedGuidePayload,
  permissionStatusSchema,
} from "./schemas";
import { assertKnownCharacterId } from "./character-match";

async function audit(action: string, status: string, detail: unknown): Promise<void> {
  await prisma.guideAdminAuditLog.create({
    data: {
      action,
      status,
      detail: JSON.stringify(detail).slice(0, 4_000),
    },
  });
}

export async function getGuideAdminOverview() {
  const [channels, videos, jobs, recommendations, audits] = await Promise.all([
    prisma.guideChannel.findMany({ orderBy: { updatedAt: "desc" }, take: 100 }),
    prisma.guideVideo.findMany({
      orderBy: { updatedAt: "desc" },
      take: 200,
      include: { channel: { select: { title: true, permissionStatus: true } } },
    }),
    prisma.guideAnalysisJob.findMany({ orderBy: { createdAt: "desc" }, take: 50 }),
    prisma.characterBuildRecommendation.findMany({
      orderBy: { updatedAt: "desc" },
      take: 100,
      include: {
        evidence: true,
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
      evidence: row.evidence,
      revisions: row.revisions,
    })),
    audits,
  };
}

function safeJson<T>(raw: string, fallback: T): T {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
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
    await prisma.guideVideo.upsert({
      where: { videoId: video.videoId },
      create: {
        videoId: video.videoId,
        channelId: video.channelId,
        title: video.title,
        description: video.description,
        publishedAt: video.publishedAt,
        thumbnailUrl: video.thumbnailUrl,
        metadataHash: video.metadataHash,
        sourceUrl: video.sourceUrl,
      },
      update: {
        title: video.title,
        description: video.description,
        publishedAt: video.publishedAt,
        thumbnailUrl: video.thumbnailUrl,
        metadataHash: video.metadataHash,
        sourceUrl: video.sourceUrl,
      },
    });
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
  await prisma.guideImportLog.create({
    data: {
      source: "youtube",
      action: "syncChannelVideos",
      status: "ok",
      detail: JSON.stringify({ channelId: input.channelId, upserted }),
    },
  });
  await audit("syncChannelVideos", "ok", { channelId: input.channelId, upserted });
  return { upserted, totalFetched: videos.length };
}

export async function upsertAnalysisJob(input: {
  jobId?: string;
  videoId: string;
  transcriptHash: string;
  inputFormat: string;
  status: string;
  modelIdentifier: string;
  promptVersion: string;
  schemaVersion: string;
  characterDataVersion: string;
  segmentCount: number;
  charCount: number;
  attempts?: number;
  usagePayload?: string;
  errorCode?: string;
}) {
  if (input.jobId) {
    return prisma.guideAnalysisJob.update({
      where: { id: input.jobId },
      data: {
        status: input.status,
        attempts: input.attempts ?? 0,
        usagePayload: input.usagePayload ?? "",
        errorCode: input.errorCode ?? "",
        completedAt: input.status === "failed" || input.status === "succeeded"
          ? new Date()
          : null,
      },
    });
  }
  return prisma.guideAnalysisJob.create({
    data: {
      videoId: input.videoId,
      transcriptHash: input.transcriptHash,
      inputFormat: input.inputFormat,
      status: input.status,
      modelIdentifier: input.modelIdentifier,
      promptVersion: input.promptVersion,
      schemaVersion: input.schemaVersion,
      characterDataVersion: input.characterDataVersion,
      segmentCount: input.segmentCount,
      charCount: input.charCount,
      attempts: input.attempts ?? 0,
      usagePayload: input.usagePayload ?? "",
      errorCode: input.errorCode ?? "",
    },
  });
}

export async function getCachedGuideResult(cacheKey: string): Promise<{
  jobId: string;
  recommendationId?: string;
  characterId?: string;
  status: string;
} | null> {
  const result = await prisma.guideAnalysisResult.findUnique({ where: { cacheKey } });
  if (!result || result.status !== "validated") return null;
  const recommendation = result.characterId
    ? await prisma.characterBuildRecommendation.findFirst({
        where: {
          characterId: result.characterId,
          status: { in: ["pending_review", "approved", "published"] },
        },
        orderBy: { updatedAt: "desc" },
      })
    : null;
  const job = await prisma.guideAnalysisJob.findFirst({
    where: {
      videoId: result.videoId,
      transcriptHash: result.transcriptHash,
      status: { in: ["succeeded", "running"] },
    },
    orderBy: { createdAt: "desc" },
  });
  return {
    jobId: job?.id ?? createHash("sha256").update(cacheKey).digest("hex").slice(0, 24),
    recommendationId: recommendation?.id,
    characterId: result.characterId || undefined,
    status: result.status,
  };
}

export async function saveGuideAnalysisArtifacts(input: {
  jobId: string;
  cacheKey: string;
  videoId: string;
  transcriptHash: string;
  characterId: string;
  modelIdentifier: string;
  promptVersion: string;
  schemaVersion: string;
  characterDataVersion: string;
  rawAiOutput: string;
  validated: ValidatedGuidePayload;
  usagePayload: string;
  attempts: number;
}) {
  const result = await prisma.guideAnalysisResult.upsert({
    where: { cacheKey: input.cacheKey },
    create: {
      cacheKey: input.cacheKey,
      videoId: input.videoId,
      transcriptHash: input.transcriptHash,
      characterId: input.characterId,
      modelIdentifier: input.modelIdentifier,
      promptVersion: input.promptVersion,
      schemaVersion: input.schemaVersion,
      characterDataVersion: input.characterDataVersion,
      status: "validated",
      rawAiOutput: input.rawAiOutput.slice(0, 200_000),
      validatedPayload: JSON.stringify(input.validated),
      generatedAt: new Date(),
    },
    update: {
      characterId: input.characterId,
      status: "validated",
      rawAiOutput: input.rawAiOutput.slice(0, 200_000),
      validatedPayload: JSON.stringify(input.validated),
      errorCode: "",
      generatedAt: new Date(),
    },
  });

  await prisma.guideExtractedClaim.deleteMany({
    where: { videoId: input.videoId, characterId: input.characterId },
  });
  for (const target of input.validated.targets) {
    await prisma.guideExtractedClaim.create({
      data: {
        videoId: input.videoId,
        characterId: input.characterId,
        claimKey: `target.${target.stat}`,
        claimPayload: JSON.stringify(target),
        confidence: target.confidence ?? input.validated.overallConfidence,
        evidencePayload: JSON.stringify(target.evidence ?? {}),
      },
    });
  }

  await prisma.guideAnalysisJob.update({
    where: { id: input.jobId },
    data: {
      status: "succeeded",
      attempts: input.attempts,
      usagePayload: input.usagePayload,
      errorCode: "",
      completedAt: new Date(),
    },
  });
  await prisma.guideVideo.update({
    where: { videoId: input.videoId },
    data: { analysisStatus: "analyzed" },
  });
  return result;
}

export async function createPendingRecommendationFromPayload(input: {
  characterId: string;
  videoId: string;
  payload: ValidatedGuidePayload;
  origin: "single_video" | "merged";
  manifestId?: string;
}): Promise<string> {
  if (!(await assertKnownCharacterId(input.characterId))) {
    throw new Error("unknownCharacterId");
  }
  const video = await prisma.guideVideo.findUnique({
    where: { videoId: input.videoId },
    include: { channel: true },
  });
  if (!video) throw new Error("videoNotFound");

  const recommendation = await prisma.characterBuildRecommendation.create({
    data: {
      characterId: input.characterId,
      status: "pending_review",
      origin: input.origin,
      manifestId: input.manifestId,
      contextPayload: JSON.stringify(input.payload.context),
      mainStatsPayload: JSON.stringify(input.payload.mainStats),
      priorityPayload: JSON.stringify(input.payload.substatPriority),
      targetsPayload: JSON.stringify(input.payload.targets),
      overallConfidence: input.payload.overallConfidence,
      notes: (input.payload.caveats ?? []).join("\n"),
    },
  });

  await prisma.recommendationSourceContribution.create({
    data: {
      recommendationId: recommendation.id,
      videoId: input.videoId,
      fieldPath: "*",
      valuePayload: JSON.stringify(input.payload),
      inclusion: "included",
    },
  });

  for (const target of input.payload.targets) {
    if (!target.evidence?.snippet) continue;
    await prisma.characterBuildRecommendationEvidence.create({
      data: {
        recommendationId: recommendation.id,
        videoId: input.videoId,
        fieldPath: `targets.${target.stat}`,
        snippet: target.evidence.snippet.slice(0, 200),
        startMs: target.evidence.startMs ?? null,
        endMs: target.evidence.endMs ?? null,
        segmentIndex: target.evidence.segmentIndex ?? null,
      },
    });
  }

  await prisma.guideRecommendationRevision.create({
    data: {
      recommendationId: recommendation.id,
      action: "created",
      afterPayload: JSON.stringify({
        status: "pending_review",
        characterId: input.characterId,
      }),
    },
  });
  await audit("createRecommendation", "ok", {
    recommendationId: recommendation.id,
    characterId: input.characterId,
  });
  return recommendation.id;
}

export async function setRecommendationStatus(input: {
  recommendationId: string;
  status: "approved" | "rejected" | "published" | "pending_review";
  adminNotes?: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
    include: {
      contributions: { include: { video: { include: { channel: true } } } },
    },
  });
  if (!existing) throw new Error("recommendationNotFound");

  if (input.status === "published") {
    for (const contribution of existing.contributions) {
      if (contribution.video.channel.permissionStatus !== "approved_for_processing") {
        throw new Error("permissionNotApproved");
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
  payload: ValidatedGuidePayload;
  adminNotes?: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
  });
  if (!existing) throw new Error("recommendationNotFound");
  const row = await prisma.characterBuildRecommendation.update({
    where: { id: input.recommendationId },
    data: {
      contextPayload: JSON.stringify(input.payload.context),
      mainStatsPayload: JSON.stringify(input.payload.mainStats),
      priorityPayload: JSON.stringify(input.payload.substatPriority),
      targetsPayload: JSON.stringify(input.payload.targets),
      overallConfidence: input.payload.overallConfidence,
      notes: input.payload.caveats.join("\n"),
      adminNotes: input.adminNotes ?? existing.adminNotes,
      status: "pending_review",
      publishedAt: null,
    },
  });
  await prisma.guideRecommendationRevision.create({
    data: {
      recommendationId: row.id,
      action: "override",
      beforePayload: JSON.stringify({
        targets: safeJson(existing.targetsPayload, []),
      }),
      afterPayload: JSON.stringify(input.payload),
    },
  });
  await audit("overrideRecommendation", "ok", { recommendationId: row.id });
  return row;
}

export async function mergeVideoRecommendations(input: {
  characterId: string;
  videoIds: string[];
}) {
  if (!(await assertKnownCharacterId(input.characterId))) {
    throw new Error("unknownCharacterId");
  }
  const results = await prisma.guideAnalysisResult.findMany({
    where: {
      characterId: input.characterId,
      videoId: { in: input.videoIds },
      status: "validated",
    },
  });
  if (results.length === 0) throw new Error("noValidatedResults");

  const sources = results.map((row) => ({
    videoId: row.videoId,
    payload: safeJson(row.validatedPayload, null) as ValidatedGuidePayload | null,
  }));
  if (sources.some((s) => !s.payload)) throw new Error("invalidStoredPayload");

  const merged = mergeGuidePayloads(
    input.characterId,
    sources.map((s) => ({ videoId: s.videoId, payload: s.payload! })),
  );
  const manifestHash = buildManifestHash(input.characterId, merged.sourceVideoIds);
  const manifest = await prisma.guideAnalysisSourceManifest.upsert({
    where: { manifestHash },
    create: {
      characterId: input.characterId,
      videoIdsPayload: JSON.stringify(merged.sourceVideoIds),
      manifestHash,
      status: "draft",
      mergePayload: JSON.stringify(merged.payload),
      conflictPayload: JSON.stringify(merged.conflicts),
    },
    update: {
      mergePayload: JSON.stringify(merged.payload),
      conflictPayload: JSON.stringify(merged.conflicts),
      status: "draft",
    },
  });
  await prisma.guideAnalysisSourceVideo.deleteMany({ where: { manifestId: manifest.id } });
  await prisma.guideAnalysisSourceVideo.createMany({
    data: merged.sourceVideoIds.map((videoId, sortOrder) => ({
      manifestId: manifest.id,
      videoId,
      sortOrder,
    })),
  });

  const recommendationId = await createPendingRecommendationFromPayload({
    characterId: input.characterId,
    videoId: merged.sourceVideoIds[0]!,
    payload: merged.payload,
    origin: "merged",
    manifestId: manifest.id,
  });
  for (const videoId of merged.sourceVideoIds.slice(1)) {
    await prisma.recommendationSourceContribution.create({
      data: {
        recommendationId,
        videoId,
        fieldPath: "*",
        valuePayload: "{}",
        inclusion: "included",
      },
    });
  }
  return { recommendationId, manifestId: manifest.id, conflicts: merged.conflicts };
}

export async function setContributionInclusion(input: {
  contributionId: string;
  inclusion: "included" | "excluded";
  reason?: string;
}) {
  const row = await prisma.recommendationSourceContribution.update({
    where: { id: input.contributionId },
    data: {
      inclusion: input.inclusion,
      reason: input.reason ?? "",
    },
  });
  await audit("setContributionInclusion", "ok", input);
  return row;
}

export async function deleteTranscriptArtifacts(videoId: string) {
  await prisma.guideAnalysisResult.updateMany({
    where: { videoId },
    data: { rawAiOutput: "" },
  });
  await prisma.guideAnalysisJob.updateMany({
    where: { videoId },
    data: { status: "transcript_cleared" },
  });
  await audit("deleteTranscriptData", "ok", { videoId });
  return { ok: true };
}

export async function getPublishedBuildRecommendation(
  characterId: string,
): Promise<PublicBuildRecommendation | null> {
  const row = await prisma.characterBuildRecommendation.findFirst({
    where: { characterId, status: "published" },
    orderBy: { publishedAt: "desc" },
    include: {
      evidence: true,
      contributions: {
        where: { inclusion: "included" },
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
      inferred?: boolean;
    }>
  )
    .filter((t) => !t.inferred)
    .map((t) => ({
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
      : ["条件付き効果・編成バフは含みません。動画内の目安です。"],
    lastVerifiedAt: row.lastVerifiedAt?.toISOString() ?? null,
    publishedAt: row.publishedAt?.toISOString() ?? null,
    sources: row.contributions.map((c) => ({
      videoId: c.video.videoId,
      title: c.video.title,
      channelTitle: c.video.channel.title,
      sourceUrl: c.video.sourceUrl,
      publishedAt: c.video.publishedAt?.toISOString() ?? null,
    })),
    evidence: row.evidence.map((e) => ({
      fieldPath: e.fieldPath,
      snippet: e.snippet.slice(0, 200),
      startMs: e.startMs,
      endMs: e.endMs,
      videoId: e.videoId,
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
