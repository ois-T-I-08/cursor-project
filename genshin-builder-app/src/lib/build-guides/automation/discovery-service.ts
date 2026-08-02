import "server-only";

import { prisma } from "@/lib/db";
import { loadCharacterHints } from "../character-match";
import {
  YoutubeGuideClient,
  type YoutubeVideoInfo,
} from "../youtube-client";
import { evaluateDiscoveryCandidate } from "./discovery-policy";
import { discoveryIdempotencyKey } from "./idempotency";

export type DiscoveredGuideCandidate = Readonly<{
  video: YoutubeVideoInfo;
  characterId: string;
  discoveryKey: string;
  discoveryReason: string;
}>;

export async function discoverApprovedChannelVideos(input: {
  client?: YoutubeGuideClient;
  maxChannels?: number;
  maxPagesPerChannel?: number;
} = {}): Promise<DiscoveredGuideCandidate[]> {
  const client = input.client ?? new YoutubeGuideClient();
  const channels = await prisma.guideChannel.findMany({
    where: {
      enabled: true,
      permissionStatus: "approved_for_processing",
    },
    orderBy: { channelId: "asc" },
    take: Math.max(1, Math.min(100, input.maxChannels ?? 25)),
    select: { channelId: true },
  });
  const approvedChannelIds = new Set(
    channels.map(({ channelId }) => channelId),
  );
  const hints = await loadCharacterHints();
  const candidates: DiscoveredGuideCandidate[] = [];
  for (const { channelId } of channels) {
    const channel = await client.fetchChannel(channelId);
    const videoIds = await client.listUploadVideoIds(
      channel.uploadsPlaylistId,
      { maxPages: input.maxPagesPerChannel ?? 2 },
    );
    const videos = await client.fetchVideos(videoIds);
    for (const video of videos) {
      const decision = evaluateDiscoveryCandidate({
        video,
        approvedChannelIds,
        characterHints: hints,
      });
      if (!decision.eligible) continue;
      const discoveryKey = discoveryIdempotencyKey({
        videoId: video.videoId,
        metadataHash: video.metadataHash,
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
          language: video.language,
          discoveryReason: decision.reason,
          availabilityStatus: "available",
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
          language: video.language,
          discoveryReason: decision.reason,
          availabilityStatus: "available",
          unavailableSince: null,
        },
      });
      candidates.push({
        video,
        characterId: decision.characterId,
        discoveryKey,
        discoveryReason: decision.reason,
      });
    }
  }
  return candidates.sort(
    (left, right) =>
      (right.video.publishedAt?.getTime() ?? 0) -
        (left.video.publishedAt?.getTime() ?? 0) ||
      left.video.videoId.localeCompare(right.video.videoId),
  );
}
