import "server-only";

import { prisma } from "@/lib/db";
import { buildManifestHash } from "./cache-key";
import { assertKnownCharacterId } from "./character-match";
import {
  mergeVisualRecommendationsDeterministic,
  mergeVisualRecommendationsWithDeepSeek,
} from "./deepseek-visual-merge";
import { geminiVideoCostHints } from "./gemini-settings";
import { isVisualAutoPublishEnabled } from "./visual-auto-publish-settings";
import {
  buildStructuredPayloadFromEvidences,
  normalizePublicBuildRecommendation,
} from "./public-recommendation-normalize";
import {
  ADMIN_WORKING_DRAFT_KEY,
  readAdminWorkingDraft,
  stripAdminWorkingDraft,
} from "./guide-admin-form";
import {
  listGuideMasterOptions,
  previewNormalizedRecommendation,
  validateStructuredDraft,
  validateStructuredForPublish,
} from "./structured-admin";
import { fetchArtifactSets } from "@/lib/api/amber-details";
import {
  permissionStatusSchema,
  publicBuildRecommendationSchema,
  type PublicBuildRecommendation,
} from "./visual-schemas";
import { YoutubeGuideClient, YoutubeError, parseYoutubePlaylistId } from "./youtube-client";
import {
  GENSIN_VIDEO_TITLE_MARKER,
  isGenshinTitledVideo,
} from "./genshin-video-title";
import { GUIDE_GAME_DATA_VERSION } from "./versions";
import { getYoutubeAutomationAdminOverview } from "./automation/admin-overview";

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

function parseExpectedUpdatedAt(raw: string): Date {
  const parsed = new Date(raw);
  if (!Number.isFinite(parsed.getTime())) {
    throw new Error("conflictUpdatedAt");
  }
  return parsed;
}

export async function getGuideAdminOverview() {
  const [channels, videos, jobs, evidences, recommendations, audits, automation] =
    await Promise.all([
      prisma.guideChannel.findMany({ orderBy: { updatedAt: "desc" }, take: 100 }),
      prisma.guideVideo.findMany({
        where: { title: { contains: GENSIN_VIDEO_TITLE_MARKER } },
        orderBy: [{ publishedAt: "desc" }, { updatedAt: "desc" }],
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
          contributions: {
            include: { video: { include: { channel: true } } },
          },
          revisions: { orderBy: { createdAt: "desc" }, take: 20 },
        },
      }),
      prisma.guideAdminAuditLog.findMany({ orderBy: { createdAt: "desc" }, take: 40 }),
      getYoutubeAutomationAdminOverview(),
    ]);

  const evidenceMentions = evidences.map((row) => {
    const payload = safeJson<{
      weaponMentions?: unknown[];
      artifactSetMentions?: unknown[];
    }>(row.normalizedPayload, {});
    return {
      id: row.id,
      videoId: row.videoId,
      startSeconds: row.startSeconds,
      endSeconds: row.endSeconds,
      evidenceType: row.evidenceType,
      exactVisibleText: row.exactVisibleText,
      confidence: row.confidence,
      validationStatus: row.validationStatus,
      approvalStatus: row.approvalStatus,
      exclusionCode: row.exclusionCode,
      purposeSummary: row.purposeSummary,
      weaponMentions: payload.weaponMentions ?? [],
      artifactSetMentions: payload.artifactSetMentions ?? [],
    };
  });

  return {
    channels,
    videos,
    jobs,
    evidences: evidenceMentions,
    recommendations: recommendations.map((row) => {
      const structuredRaw = safeJson<Record<string, unknown>>(row.structuredPayload, {});
      const working = readAdminWorkingDraft(structuredRaw);
      const structured = working?.structured
        ? working.structured
        : stripAdminWorkingDraft(structuredRaw);
      return {
        id: row.id,
        characterId: row.characterId,
        status: row.status,
        origin: row.origin,
        overallConfidence: row.overallConfidence,
        notes: row.notes,
        adminNotes: working?.adminNotes ?? row.adminNotes,
        publishedAt: row.publishedAt,
        lastVerifiedAt: row.lastVerifiedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        context: working?.context
          ? asRecord(working.context)
          : safeJson(row.contextPayload, {}),
        mainStats: working?.mainStats ?? safeJson(row.mainStatsPayload, []),
        substatPriority: working?.priority ?? safeJson(row.priorityPayload, []),
        targets: working?.targets ?? safeJson(row.targetsPayload, []),
        structuredPayload: structured,
        hasUnpublishedDraft: Boolean(working),
        structuredReviewStatus:
          typeof structured.structuredReviewStatus === "string"
            ? structured.structuredReviewStatus
            : null,
        pendingMentions: structured.pendingMentions ?? { weapons: [], artifactSets: [] },
        contributions: row.contributions.map((c) => ({
          id: c.id,
          videoId: c.videoId,
          startSeconds: c.startSeconds,
          endSeconds: c.endSeconds,
          exactVisibleText: c.exactVisibleText,
          contributionRole: c.contributionRole,
          decision: c.decision,
          usedInPublishedResult: c.usedInPublishedResult,
          videoTitle: c.video.title,
          channelTitle: c.video.channel.title,
          sourceUrl: c.video.sourceUrl,
          publishedAt: c.video.publishedAt,
        })),
        revisions: row.revisions,
      };
    }),
    audits,
    automation,
    geminiCost: geminiVideoCostHints(),
    visualAutoPublishEnabled: isVisualAutoPublishEnabled(),
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
  const videoIds = await client.listPlaylistVideoIds(info.uploadsPlaylistId, {
    maxPages: input.maxPages,
  });
  const videos = await client.fetchVideos(videoIds);
  let upserted = 0;
  let skippedTitle = 0;
  for (const video of videos) {
    if (video.channelId !== input.channelId) continue;
    if (!isGenshinTitledVideo(video.title)) {
      skippedTitle += 1;
      continue;
    }
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
  await audit("syncChannelVideos", "ok", {
    channelId: input.channelId,
    upserted,
    skippedTitle,
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
  });
  return {
    upserted,
    totalFetched: videos.length,
    skippedTitle,
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
  };
}

/**
 * 特定プレイリストから動画メタデータを取り込む。
 * 動画の所属チャンネルが「登録済み・有効・approved_for_processing」の場合のみ upsert。
 * 未承認チャンネルの動画はスキップ（勝手にチャンネル登録しない）。
 * タイトルに「【原神】」を含む動画のみ対象。
 */
export async function syncPlaylistVideos(input: {
  playlistId: string;
  client?: YoutubeGuideClient;
  maxPages?: number;
}) {
  const playlistId = parseYoutubePlaylistId(input.playlistId);
  if (!playlistId) throw new Error("invalidPlaylistId");

  const client = input.client ?? new YoutubeGuideClient();
  const playlist = await client.fetchPlaylist(playlistId);
  const videoIds = await client.listPlaylistVideoIds(playlistId, {
    maxPages: input.maxPages ?? 5,
  });
  const videos = await client.fetchVideos(videoIds);

  const channelIds = [...new Set(videos.map((v) => v.channelId))];
  const channels = await prisma.guideChannel.findMany({
    where: { channelId: { in: channelIds } },
  });
  const channelById = new Map(channels.map((c) => [c.channelId, c]));

  let upserted = 0;
  let skippedUnregisteredChannel = 0;
  let skippedNotApproved = 0;
  let skippedDisabled = 0;
  let skippedTitle = 0;
  const skippedChannelIds = new Set<string>();

  for (const video of videos) {
    if (!isGenshinTitledVideo(video.title)) {
      skippedTitle += 1;
      continue;
    }
    const channel = channelById.get(video.channelId);
    if (!channel) {
      skippedUnregisteredChannel += 1;
      skippedChannelIds.add(video.channelId);
      continue;
    }
    if (!channel.enabled) {
      skippedDisabled += 1;
      skippedChannelIds.add(video.channelId);
      continue;
    }
    if (channel.permissionStatus !== "approved_for_processing") {
      skippedNotApproved += 1;
      skippedChannelIds.add(video.channelId);
      continue;
    }

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
      previous.privacyStatus === "public" &&
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

  await audit("syncPlaylistVideos", "ok", {
    playlistId,
    playlistTitle: playlist.title,
    upserted,
    skippedUnregisteredChannel,
    skippedNotApproved,
    skippedDisabled,
    skippedTitle,
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
  });

  return {
    playlistId,
    playlistTitle: playlist.title,
    playlistChannelId: playlist.channelId,
    totalFetched: videos.length,
    upserted,
    skippedUnregisteredChannel,
    skippedNotApproved,
    skippedDisabled,
    skippedTitle,
    titleMarker: GENSIN_VIDEO_TITLE_MARKER,
    skippedChannelIds: [...skippedChannelIds],
    note:
      "映像解析は自動実行しません。動画モジュールから個別に解析し、承認後に公開してください。タイトルに「【原神】」を含む動画のみ取り込みます。",
  };
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
  expectedUpdatedAt: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
    include: {
      contributions: { include: { video: { include: { channel: true } }, evidence: true } },
    },
  });
  if (!existing) throw new Error("recommendationNotFound");
  const expectedUpdatedAt = parseExpectedUpdatedAt(input.expectedUpdatedAt);
  if (expectedUpdatedAt.getTime() !== existing.updatedAt.getTime()) {
    throw new Error("conflictUpdatedAt");
  }

  if (input.status === "published") {
    const publishableContributions = existing.contributions.filter((contribution) =>
      ["adopted", "partially_adopted"].includes(contribution.decision),
    );
    for (const contribution of publishableContributions) {
      if (contribution.video.channel.permissionStatus !== "approved_for_processing") {
        throw new Error("permissionNotApproved");
      }
      if (contribution.video.privacyStatus !== "public") {
        throw new Error("videoNotPublic");
      }
      if (contribution.evidence.approvalStatus !== "approved") {
        throw new Error("evidenceNotApproved");
      }
    }
    if (existing.status !== "approved" && existing.status !== "published") {
      throw new Error("notApproved");
    }
  }

  let nextStructuredPayload = existing.structuredPayload;
  let nextTargetsPayload = existing.targetsPayload;
  let nextMainStatsPayload = existing.mainStatsPayload;
  let nextPriorityPayload = existing.priorityPayload;
  let nextContextPayload = existing.contextPayload;
  let nextAdminNotes = input.adminNotes ?? existing.adminNotes;
  let nextStatus = input.status;
  let revisionAction: string = input.status;

  if (input.status === "published") {
    const structuredRaw = safeJson<Record<string, unknown>>(existing.structuredPayload, {});
    const working = readAdminWorkingDraft(structuredRaw);
    const structured = working?.structured
      ? stripAdminWorkingDraft(working.structured)
      : stripAdminWorkingDraft(structuredRaw);
    if (working?.targets != null) {
      nextTargetsPayload = JSON.stringify(working.targets);
    }
    if (working?.mainStats != null) {
      nextMainStatsPayload = JSON.stringify(working.mainStats);
    }
    if (working?.priority != null) {
      nextPriorityPayload = JSON.stringify(working.priority);
    }
    if (working?.context != null) {
      nextContextPayload = JSON.stringify(working.context);
    }
    if (working?.adminNotes != null) {
      nextAdminNotes = working.adminNotes;
    }

    const weaponRows = await prisma.weapon.findMany({ select: { id: true } });
    const knownWeaponIds = new Set(weaponRows.map((w) => w.id));
    const artifactSets = await fetchArtifactSets().catch(() => []);
    const knownSetIds = new Set(artifactSets.map((s) => s.id));
    const publishableContributions = existing.contributions.filter((contribution) =>
      ["adopted", "partially_adopted"].includes(contribution.decision),
    );
    const publishIssues = validateStructuredForPublish({
      characterId: existing.characterId,
      structured,
      mainStats: safeJson(nextMainStatsPayload, []),
      targets: safeJson(nextTargetsPayload, []),
      sources: publishableContributions.map((c, index) => ({
        id: `source-${c.videoId || index}`,
        videoId: c.videoId,
      })),
      knownWeaponIds,
      knownSetIds,
      artifactMasterAvailable: artifactSets.length > 0,
    });
    const fatal = publishIssues.filter((i) => i.level === "error");
    if (fatal.length > 0) {
      // DB 更新前に拒否 → 旧公開スナップショット維持
      throw new Error(`structuredPublishBlocked:${fatal.map((f) => f.message).join(" | ")}`);
    }
    structured.publishedContentUpdatedAt = new Date().toISOString();
    nextStructuredPayload = JSON.stringify(structured);
  }

  if (input.status === "approved") {
    const structured = stripAdminWorkingDraft(
      safeJson<Record<string, unknown>>(
        typeof nextStructuredPayload === "string"
          ? nextStructuredPayload
          : existing.structuredPayload,
        {},
      ),
    );
    // 承認は作業下書き側を優先
    const working = readAdminWorkingDraft(
      safeJson(existing.structuredPayload, {}),
    );
    const base = working?.structured
      ? stripAdminWorkingDraft(working.structured)
      : structured;
    base.structuredReviewStatus = "admin_confirmed";
    if (working) {
      nextStructuredPayload = JSON.stringify({
        ...stripAdminWorkingDraft(safeJson(existing.structuredPayload, {})),
        [ADMIN_WORKING_DRAFT_KEY]: {
          ...working,
          structured: base,
        },
      });
      if (existing.status === "published") {
        // 作業下書きの承認では旧公開スナップショットを維持する。
        nextStatus = "published";
        revisionAction = "approve_draft";
      }
    } else {
      nextStructuredPayload = JSON.stringify(base);
      if (existing.status === "published") {
        nextStatus = "published";
        revisionAction = "approve_published";
      }
    }
  }

  const updateLastVerifiedAt =
    revisionAction !== "approve_draft" &&
    (input.status === "approved" || input.status === "published");
  const updateData = {
      status: input.status,
      adminNotes: nextAdminNotes,
      structuredPayload: nextStructuredPayload,
      targetsPayload: nextTargetsPayload,
      mainStatsPayload: nextMainStatsPayload,
      priorityPayload: nextPriorityPayload,
      contextPayload: nextContextPayload,
      publishedAt:
        nextStatus === "published"
          ? input.status === "published"
            ? new Date()
            : existing.publishedAt
          : null,
      lastVerifiedAt: updateLastVerifiedAt
        ? new Date()
        : existing.lastVerifiedAt,
    } as const;
  const row = await prisma.$transaction(async (tx) => {
    const result = await tx.characterBuildRecommendation.updateMany({
      where: {
        id: input.recommendationId,
        updatedAt: expectedUpdatedAt,
      },
      data: { ...updateData, status: nextStatus },
    });
    if (result.count !== 1) throw new Error("conflictUpdatedAt");
    const updated = await tx.characterBuildRecommendation.findUnique({
      where: { id: input.recommendationId },
    });
    if (!updated) throw new Error("recommendationNotFound");

    if (input.status === "published") {
      await tx.recommendationVisualContribution.updateMany({
        where: { recommendationId: updated.id },
        data: { usedInPublishedResult: false },
      });
      await tx.recommendationVisualContribution.updateMany({
        where: {
          recommendationId: updated.id,
          decision: { in: ["adopted", "partially_adopted"] },
        },
        data: { usedInPublishedResult: true },
      });
    } else if (nextStatus !== "published") {
      await tx.recommendationVisualContribution.updateMany({
        where: { recommendationId: updated.id },
        data: { usedInPublishedResult: false },
      });
    }

    await tx.guideRecommendationRevision.create({
      data: {
        recommendationId: updated.id,
        action: revisionAction,
        beforePayload: JSON.stringify({ status: existing.status }),
        afterPayload: JSON.stringify({ status: updated.status }),
      },
    });
    await tx.guideAdminAuditLog.create({
      data: {
        action: "setRecommendationStatus",
        status: "ok",
        detail: JSON.stringify({
          recommendationId: updated.id,
          requestedStatus: input.status,
          resultingStatus: updated.status,
        }).slice(0, 4_000),
      },
    });
    return updated;
  });
  return row;
}

export async function unpublishRecommendation(
  recommendationId: string,
  expectedUpdatedAtRaw: string,
) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: recommendationId },
  });
  if (!existing) throw new Error("recommendationNotFound");
  const expectedUpdatedAt = parseExpectedUpdatedAt(expectedUpdatedAtRaw);
  if (expectedUpdatedAt.getTime() !== existing.updatedAt.getTime()) {
    throw new Error("conflictUpdatedAt");
  }
  const row = await prisma.$transaction(async (tx) => {
    const result = await tx.characterBuildRecommendation.updateMany({
      where: { id: recommendationId, updatedAt: expectedUpdatedAt },
      data: { status: "approved", publishedAt: null },
    });
    if (result.count !== 1) throw new Error("conflictUpdatedAt");
    const updated = await tx.characterBuildRecommendation.findUnique({
      where: { id: recommendationId },
    });
    if (!updated) throw new Error("recommendationNotFound");
    await tx.recommendationVisualContribution.updateMany({
      where: { recommendationId: updated.id },
      data: { usedInPublishedResult: false },
    });
    await tx.guideRecommendationRevision.create({
      data: {
        recommendationId: updated.id,
        action: "unpublish",
        beforePayload: JSON.stringify({
          status: existing.status,
          publishedAt: existing.publishedAt,
          structured: safeJson(existing.structuredPayload, {}),
          targets: safeJson(existing.targetsPayload, []),
          mainStats: safeJson(existing.mainStatsPayload, []),
        }),
        afterPayload: JSON.stringify({
          status: updated.status,
          publishedAt: null,
          structured: safeJson(updated.structuredPayload, {}),
          targets: safeJson(updated.targetsPayload, []),
          mainStats: safeJson(updated.mainStatsPayload, []),
        }),
      },
    });
    await tx.guideAdminAuditLog.create({
      data: {
        action: "unpublishRecommendation",
        status: "ok",
        detail: JSON.stringify({ recommendationId: updated.id }),
      },
    });
    return updated;
  });
  return row;
}

export async function overrideRecommendation(input: {
  recommendationId: string;
  targetsPayload: unknown;
  mainStatsPayload?: unknown;
  priorityPayload?: unknown;
  contextPayload?: unknown;
  structuredPayload?: unknown;
  adminNotes?: string;
  expectedUpdatedAt: string;
  keepPublished?: boolean;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
  });
  if (!existing) throw new Error("recommendationNotFound");

  const expectedUpdatedAt = parseExpectedUpdatedAt(input.expectedUpdatedAt);
  if (expectedUpdatedAt.getTime() !== existing.updatedAt.getTime()) {
    throw new Error("conflictUpdatedAt");
  }

  const incomingStructured =
    input.structuredPayload === undefined
      ? stripAdminWorkingDraft(safeJson(existing.structuredPayload, {}))
      : typeof input.structuredPayload === "string"
        ? stripAdminWorkingDraft(safeJson(input.structuredPayload, {}))
        : stripAdminWorkingDraft(asRecord(input.structuredPayload));

  const weaponRows = await prisma.weapon.findMany({ select: { id: true } });
  const artifactSets = await fetchArtifactSets().catch(() => []);
  const draftIssues = validateStructuredDraft({
    characterId: existing.characterId,
    structured: incomingStructured,
    mainStats: input.mainStatsPayload ?? safeJson(existing.mainStatsPayload, []),
    targets: input.targetsPayload,
    knownWeaponIds: new Set(weaponRows.map((w) => w.id)),
    knownSetIds: new Set(artifactSets.map((s) => s.id)),
    artifactMasterAvailable: artifactSets.length > 0,
  });
  if (draftIssues.some((i) => i.level === "error")) {
    throw new Error(
      `structuredDraftInvalid:${draftIssues
        .filter((i) => i.level === "error")
        .map((i) => i.message)
        .join(" | ")}`,
    );
  }

  const keepPublishedLive =
    Boolean(input.keepPublished) && existing.status === "published";

  let nextStructuredPayload: string;
  let nextTargets = existing.targetsPayload;
  let nextMainStats = existing.mainStatsPayload;
  let nextPriority = existing.priorityPayload;
  let nextContext = existing.contextPayload;
  let nextStatus = existing.status;
  let nextPublishedAt = existing.publishedAt;

  if (keepPublishedLive) {
    // 公開中レスポンスは据え置き。編集内容は adminWorkingDraft のみに保存。
    // publishedContentUpdatedAt は触らない（公開 API の updatedAt / ETag を維持）。
    const publishedStructured = stripAdminWorkingDraft(
      safeJson(existing.structuredPayload, {}),
    );
    nextStructuredPayload = JSON.stringify({
      ...publishedStructured,
      [ADMIN_WORKING_DRAFT_KEY]: {
        structured: incomingStructured,
        targets: input.targetsPayload,
        mainStats:
          input.mainStatsPayload ?? safeJson(existing.mainStatsPayload, []),
        priority:
          input.priorityPayload ?? safeJson(existing.priorityPayload, []),
        context:
          input.contextPayload ?? safeJson(existing.contextPayload, {}),
        adminNotes: input.adminNotes ?? existing.adminNotes,
        savedAt: new Date().toISOString(),
      },
    });
  } else {
    nextStructuredPayload = JSON.stringify(incomingStructured);
    nextTargets = JSON.stringify(input.targetsPayload);
    nextMainStats = JSON.stringify(
      input.mainStatsPayload ?? safeJson(existing.mainStatsPayload, []),
    );
    nextPriority = JSON.stringify(
      input.priorityPayload ?? safeJson(existing.priorityPayload, []),
    );
    nextContext = JSON.stringify(
      input.contextPayload ?? safeJson(existing.contextPayload, {}),
    );
    if (existing.status === "published") {
      nextStatus = "pending_review";
      nextPublishedAt = null;
    }
  }

  const updateData = {
      targetsPayload: nextTargets,
      mainStatsPayload: nextMainStats,
      priorityPayload: nextPriority,
      contextPayload: nextContext,
      structuredPayload: nextStructuredPayload,
      adminNotes: input.adminNotes ?? existing.adminNotes,
      status: nextStatus,
      publishedAt: nextPublishedAt,
    } as const;
  const row = await prisma.$transaction(async (tx) => {
    const result = await tx.characterBuildRecommendation.updateMany({
      where: {
        id: input.recommendationId,
        updatedAt: expectedUpdatedAt,
      },
      data: updateData,
    });
    if (result.count !== 1) throw new Error("conflictUpdatedAt");
    const updated = await tx.characterBuildRecommendation.findUnique({
      where: { id: input.recommendationId },
    });
    if (!updated) throw new Error("recommendationNotFound");
    await tx.guideRecommendationRevision.create({
      data: {
        recommendationId: updated.id,
        action: keepPublishedLive ? "override_draft" : "override",
        beforePayload: JSON.stringify({
          targets: safeJson(existing.targetsPayload, []),
          mainStats: safeJson(existing.mainStatsPayload, []),
          structured: safeJson(existing.structuredPayload, {}),
          status: existing.status,
        }),
        afterPayload: JSON.stringify({
          targets: input.targetsPayload,
          mainStats:
            input.mainStatsPayload ?? safeJson(existing.mainStatsPayload, []),
          structured: incomingStructured,
          status: updated.status,
          keepPublished: keepPublishedLive,
        }),
      },
    });
    await tx.guideAdminAuditLog.create({
      data: {
        action: "overrideRecommendation",
        status: "ok",
        detail: JSON.stringify({
          recommendationId: updated.id,
          keepPublished: keepPublishedLive,
          warnings: draftIssues.filter((i) => i.level === "warning").length,
        }).slice(0, 4_000),
      },
    });
    return updated;
  });
  return { recommendation: row, warnings: draftIssues, keepPublished: keepPublishedLive };
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

export async function validateStructuredRecommendationDto(input: {
  recommendationId: string;
  targetsPayload?: unknown;
  mainStatsPayload?: unknown;
  structuredPayload?: unknown;
}) {
  const row = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
    include: {
      contributions: { include: { video: { include: { channel: true } } } },
    },
  });
  if (!row) throw new Error("recommendationNotFound");

  const structuredRaw =
    input.structuredPayload === undefined
      ? safeJson<Record<string, unknown>>(row.structuredPayload, {})
      : typeof input.structuredPayload === "string"
        ? safeJson<Record<string, unknown>>(input.structuredPayload, {})
        : asRecord(input.structuredPayload);
  const working =
    input.structuredPayload === undefined
      ? readAdminWorkingDraft(structuredRaw)
      : null;
  const structured = working?.structured
    ? stripAdminWorkingDraft(working.structured)
    : stripAdminWorkingDraft(structuredRaw);
  const mainStats =
    input.mainStatsPayload ??
    working?.mainStats ??
    safeJson(row.mainStatsPayload, []);
  const targets =
    input.targetsPayload ?? working?.targets ?? safeJson(row.targetsPayload, []);
  const weaponRows = await prisma.weapon.findMany({ select: { id: true } });
  const knownWeaponIds = new Set(weaponRows.map((w) => w.id));
  const artifactSets = await fetchArtifactSets().catch(() => []);
  const knownSetIds = new Set(artifactSets.map((s) => s.id));
  const publishableContributions = row.contributions.filter((contribution) =>
    ["adopted", "partially_adopted"].includes(contribution.decision),
  );
  const sources = publishableContributions.map((c, index) => ({
    id: `source-${c.videoId || index}`,
    videoId: c.videoId,
    title: c.video.title,
    channelId: c.video.channel.channelId,
    channelTitle: c.video.channel.title,
    sourceUrl: c.video.sourceUrl,
    publishedAt: c.video.publishedAt?.toISOString() ?? null,
  }));

  const draftIssues = validateStructuredDraft({
    characterId: row.characterId,
    structured,
    mainStats,
    targets,
    knownWeaponIds,
    knownSetIds,
    artifactMasterAvailable: artifactSets.length > 0,
  });
  const publishIssues = validateStructuredForPublish({
    characterId: row.characterId,
    structured,
    mainStats,
    targets,
    sources,
    knownWeaponIds,
    knownSetIds,
    artifactMasterAvailable: artifactSets.length > 0,
  });
  const preview = previewNormalizedRecommendation({
    characterId: row.characterId,
    origin: row.origin,
    overallConfidence: row.overallConfidence,
    context: safeJson(row.contextPayload, {}),
    mainStats,
    substatPriority: safeJson(row.priorityPayload, []),
    targets,
    structured,
    sources,
    lastVerifiedAt: row.lastVerifiedAt?.toISOString() ?? null,
    publishedAt: row.publishedAt?.toISOString() ?? null,
    updatedAt: row.updatedAt.toISOString(),
  });

  return {
    draftIssues,
    publishIssues,
    canPublish: !publishIssues.some((i) => i.level === "error"),
    preview,
  };
}

export async function previewRecommendationPublicDto(recommendationId: string) {
  const row = await prisma.characterBuildRecommendation.findUnique({
    where: { id: recommendationId },
    include: {
      contributions: { include: { video: { include: { channel: true } } } },
    },
  });
  if (!row) throw new Error("recommendationNotFound");
  const structuredRaw = safeJson<Record<string, unknown>>(row.structuredPayload, {});
  const working = readAdminWorkingDraft(structuredRaw);
  const structured = working?.structured
    ? stripAdminWorkingDraft(working.structured)
    : stripAdminWorkingDraft(structuredRaw);
  const publishableContributions = row.contributions.filter((contribution) =>
    ["adopted", "partially_adopted"].includes(contribution.decision),
  );
  return previewNormalizedRecommendation({
    characterId: row.characterId,
    origin: row.origin,
    overallConfidence: row.overallConfidence,
    context: working?.context
      ? asRecord(working.context)
      : safeJson(row.contextPayload, {}),
    mainStats: working?.mainStats ?? safeJson(row.mainStatsPayload, []),
    substatPriority: working?.priority ?? safeJson(row.priorityPayload, []),
    targets: working?.targets ?? safeJson(row.targetsPayload, []),
    structured,
    sources: publishableContributions.map((c) => ({
      videoId: c.video.videoId,
      title: c.video.title,
      channelId: c.video.channel.channelId,
      channelTitle: c.video.channel.title,
      sourceUrl: c.video.sourceUrl,
      publishedAt: c.video.publishedAt?.toISOString() ?? null,
      reviewedAt: row.lastVerifiedAt?.toISOString() ?? null,
      gameVersion:
        typeof structured.gameVersion === "string" ? structured.gameVersion : null,
    })),
    evidence: publishableContributions.map((c) => ({
      fieldPath: "visual",
      exactVisibleText: c.exactVisibleText.slice(0, 200),
      startSeconds: c.startSeconds,
      endSeconds: c.endSeconds,
      videoId: c.videoId,
    })),
    lastVerifiedAt: row.lastVerifiedAt?.toISOString() ?? null,
    publishedAt: row.publishedAt?.toISOString() ?? null,
    updatedAt: row.updatedAt.toISOString(),
  });
}

export async function restoreRecommendationRevision(input: {
  recommendationId: string;
  revisionId: string;
  expectedUpdatedAt: string;
}) {
  const existing = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
  });
  if (!existing) throw new Error("recommendationNotFound");
  const expectedUpdatedAt = parseExpectedUpdatedAt(input.expectedUpdatedAt);
  if (expectedUpdatedAt.getTime() !== existing.updatedAt.getTime()) {
    throw new Error("conflictUpdatedAt");
  }
  const revision = await prisma.guideRecommendationRevision.findFirst({
    where: { id: input.revisionId, recommendationId: input.recommendationId },
  });
  if (!revision) throw new Error("revisionNotFound");
  const before = safeJson<{
    targets?: unknown;
    mainStats?: unknown;
    structured?: unknown;
  }>(revision.beforePayload, {});
  if (before.targets == null && before.structured == null) {
    throw new Error("revisionNotRestorable");
  }
  const beforeStructured = asRecord(before.structured);
  const previousWorking = readAdminWorkingDraft(beforeStructured);
  // 公開中は予告なく公開スナップショットを上書きしない（working draft へ復元）
  return overrideRecommendation({
    recommendationId: input.recommendationId,
    targetsPayload:
      previousWorking?.targets ??
      before.targets ??
      safeJson(existing.targetsPayload, []),
    mainStatsPayload: previousWorking?.mainStats ?? before.mainStats,
    priorityPayload: previousWorking?.priority,
    contextPayload: previousWorking?.context,
    structuredPayload: previousWorking?.structured ?? before.structured,
    adminNotes: previousWorking?.adminNotes,
    expectedUpdatedAt: input.expectedUpdatedAt,
    keepPublished: existing.status === "published",
  });
}

export { listGuideMasterOptions };

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

  const structuredPayload = buildStructuredPayloadFromEvidences(
    evidences.map((e) => ({
      videoId: e.videoId,
      normalizedPayload: e.normalizedPayload,
    })),
  );

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
      structuredPayload,
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

  const structured = stripAdminWorkingDraft(
    safeJson<Record<string, unknown>>(row.structuredPayload, {}),
  );
  // working draft 保存で row.updatedAt が動いても公開 ETag を動かさない
  const publicUpdatedAt =
    typeof structured.publishedContentUpdatedAt === "string"
      ? structured.publishedContentUpdatedAt
      : (row.publishedAt?.toISOString() ?? row.updatedAt.toISOString());

  const { data: normalized } = normalizePublicBuildRecommendation({
    characterId: row.characterId,
    origin: row.origin === "merged" ? "merged" : "single_video",
    overallConfidence: row.overallConfidence,
    context: safeJson(row.contextPayload, {}),
    mainStats: safeJson(row.mainStatsPayload, []),
    substatPriority: safeJson(row.priorityPayload, []),
    targets,
    structured,
    weapons: structured.weapons,
    artifactRecommendations: structured.artifactRecommendations,
    investmentPriority: structured.investmentPriority,
    gameVersion: structured.gameVersion,
    recommendedStats: structured.recommendedStats,
    caveats: row.notes
      ? row.notes.split("\n").filter(Boolean)
      : ["条件付き効果・編成バフは含みません。動画画面内で確認した目安です。"],
    lastVerifiedAt: row.lastVerifiedAt?.toISOString() ?? null,
    publishedAt: row.publishedAt?.toISOString() ?? null,
    updatedAt: publicUpdatedAt,
    sources: row.contributions.map((c) => ({
      videoId: c.video.videoId,
      title: c.video.title,
      channelId: c.video.channel.channelId ?? null,
      channelTitle: c.video.channel.title,
      sourceUrl: c.video.sourceUrl,
      publishedAt: c.video.publishedAt?.toISOString() ?? null,
      reviewedAt: row.lastVerifiedAt?.toISOString() ?? null,
      gameVersion:
        typeof structured.gameVersion === "string" ? structured.gameVersion : null,
    })),
    evidence: row.contributions.map((c) => ({
      fieldPath: "visual",
      exactVisibleText: c.exactVisibleText.slice(0, 200),
      startSeconds: c.startSeconds,
      endSeconds: c.endSeconds,
      videoId: c.videoId,
    })),
  });

  return publicBuildRecommendationSchema.parse(normalized);
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
