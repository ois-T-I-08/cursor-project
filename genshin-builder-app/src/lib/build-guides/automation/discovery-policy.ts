import {
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
  type CharacterHint,
} from "../character-match-logic";
import type { YoutubeVideoInfo } from "../youtube-client";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

export type DiscoveryDecision =
  | {
      eligible: true;
      characterId: string;
      reason: "APPROVED_CHANNEL_EXACT_CHARACTER_BUILD_GUIDE";
    }
  | {
      eligible: false;
      blockCode:
        | "DISCOVERY_CHANNEL_NOT_APPROVED"
        | "DISCOVERY_NOT_PUBLIC"
        | "DISCOVERY_LIVE_OR_PREMIERE"
        | "DISCOVERY_POTENTIAL_SHORT"
        | "DISCOVERY_DURATION_UNKNOWN"
        | "DISCOVERY_NOT_BUILD_GUIDE"
        | "DISCOVERY_CHARACTER_UNRESOLVED";
    };

export function evaluateDiscoveryCandidate(input: {
  video: YoutubeVideoInfo;
  approvedChannelIds: ReadonlySet<string>;
  characterHints: readonly CharacterHint[];
}): DiscoveryDecision {
  const { video } = input;
  if (!input.approvedChannelIds.has(video.channelId)) {
    return { eligible: false, blockCode: "DISCOVERY_CHANNEL_NOT_APPROVED" };
  }
  if (video.privacyStatus !== "public") {
    return { eligible: false, blockCode: "DISCOVERY_NOT_PUBLIC" };
  }
  if (
    video.liveBroadcastContent === "live" ||
    video.liveBroadcastContent === "upcoming"
  ) {
    return { eligible: false, blockCode: "DISCOVERY_LIVE_OR_PREMIERE" };
  }
  if (video.durationSeconds == null) {
    return { eligible: false, blockCode: "DISCOVERY_DURATION_UNKNOWN" };
  }
  if (
    video.durationSeconds <= YOUTUBE_AUTOMATION_POLICY.potentialShortMaxSeconds
  ) {
    return { eligible: false, blockCode: "DISCOVERY_POTENTIAL_SHORT" };
  }
  if (!isCharacterBuildGuideTitle(video.title)) {
    return { eligible: false, blockCode: "DISCOVERY_NOT_BUILD_GUIDE" };
  }
  const characterId = resolvePrimaryCharacterFromTitle(
    video.title,
    [...input.characterHints],
  );
  if (!characterId) {
    return { eligible: false, blockCode: "DISCOVERY_CHARACTER_UNRESOLVED" };
  }
  return {
    eligible: true,
    characterId,
    reason: "APPROVED_CHANNEL_EXACT_CHARACTER_BUILD_GUIDE",
  };
}
