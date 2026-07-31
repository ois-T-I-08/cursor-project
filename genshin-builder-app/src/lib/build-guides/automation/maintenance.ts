import "server-only";

import { prisma } from "@/lib/db";
import type { YoutubeGuideClient, YoutubeVideoInfo } from "../youtube-client";

export type AvailabilityPlan = Readonly<{
  videoId: string;
  availabilityStatus: "available" | "unavailable";
  privacyStatus: string;
}>;

export function planSourceAvailability(input: {
  requestedVideoIds: readonly string[];
  fetchedVideos: readonly YoutubeVideoInfo[];
}): AvailabilityPlan[] {
  const fetched = new Map(input.fetchedVideos.map((video) => [video.videoId, video]));
  return [...new Set(input.requestedVideoIds)].sort().map((videoId) => {
    const video = fetched.get(videoId);
    return {
      videoId,
      availabilityStatus:
        video?.privacyStatus === "public" ? "available" : "unavailable",
      privacyStatus: video?.privacyStatus ?? "missing",
    };
  });
}

/**
 * Provider failure performs no writes. Successful checks update source
 * availability only; published recommendations and revisions are retained.
 */
export async function refreshPublishedSourceAvailability(input: {
  videoIds: readonly string[];
  client: Pick<YoutubeGuideClient, "fetchVideos">;
  now: Date;
}): Promise<{ checked: number; unavailable: number }> {
  const fetched = await input.client.fetchVideos([...input.videoIds]);
  const plan = planSourceAvailability({
    requestedVideoIds: input.videoIds,
    fetchedVideos: fetched,
  });
  if (plan.length === 0) return { checked: 0, unavailable: 0 };
  await prisma.$transaction(
    plan.flatMap((item) => [
      prisma.guideVideo.updateMany({
        where: { videoId: item.videoId },
        data: {
          privacyStatus: item.privacyStatus,
          availabilityStatus: item.availabilityStatus,
          ...(item.availabilityStatus === "available"
            ? { unavailableSince: null }
            : {}),
        },
      }),
      ...(item.availabilityStatus === "unavailable"
        ? [
            prisma.guideVideo.updateMany({
              where: { videoId: item.videoId, unavailableSince: null },
              data: { unavailableSince: input.now },
            }),
          ]
        : []),
    ]),
  );
  return {
    checked: plan.length,
    unavailable: plan.filter(
      ({ availabilityStatus }) => availabilityStatus === "unavailable",
    ).length,
  };
}
