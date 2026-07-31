import type { YoutubeAutomationFlags } from "./feature-flags";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

export type AutomaticPublicationQuality = Readonly<{
  sourceCount: number;
  channelAllowed: boolean;
  videoPublic: boolean;
  transcriptAvailable: boolean;
  schemaValid: boolean;
  entityCoverage: number;
  citationCoverage: number;
  timestampCoverage: number;
  evidenceMatches: boolean;
  minClaimConfidence: number;
  overallConfidence: number;
  conflicts: readonly string[];
}>;

export type AutomaticPublicationGate =
  | { allowed: true; status: "READY_TO_PUBLISH"; blockCodes: readonly [] }
  | {
      allowed: false;
      status: "READY_TO_PUBLISH" | "BLOCKED";
      blockCodes: readonly string[];
    };

export function evaluateAutomaticPublicationGate(input: {
  flags: YoutubeAutomationFlags;
  dryRun: boolean;
  emergencyStopped: boolean;
  quality: AutomaticPublicationQuality;
}): AutomaticPublicationGate {
  const blockCodes: string[] = [];
  const { quality } = input;
  if (!input.flags.enabled || !input.flags.autoPublishEnabled) {
    blockCodes.push("AUTO_PUBLISH_DISABLED");
  }
  if (input.dryRun) blockCodes.push("DRY_RUN");
  if (input.emergencyStopped) blockCodes.push("EMERGENCY_STOPPED");
  if (quality.sourceCount !== 1) {
    blockCodes.push(
      quality.sourceCount > 1
        ? "MULTI_SOURCE_REQUIRES_REVIEW"
        : "SOURCE_REQUIRED",
    );
  }
  if (!quality.channelAllowed) blockCodes.push("CHANNEL_NOT_ALLOWED");
  if (!quality.videoPublic) blockCodes.push("VIDEO_NOT_PUBLIC");
  if (!quality.transcriptAvailable) {
    blockCodes.push("BLOCKED_TRANSCRIPT_UNAVAILABLE");
  }
  if (!quality.schemaValid) blockCodes.push("BLOCKED_ANALYSIS_SCHEMA_INVALID");
  if (
    quality.entityCoverage < YOUTUBE_AUTOMATION_POLICY.requiredEntityCoverage
  ) {
    blockCodes.push("BLOCKED_UNKNOWN_ENTITY");
  }
  if (
    quality.citationCoverage <
    YOUTUBE_AUTOMATION_POLICY.requiredCitationCoverage
  ) {
    blockCodes.push("BLOCKED_UNRESOLVED_CITATION");
  }
  if (
    quality.timestampCoverage <
    YOUTUBE_AUTOMATION_POLICY.requiredTimestampCoverage
  ) {
    blockCodes.push("BLOCKED_TIMESTAMP_INVALID");
  }
  if (!quality.evidenceMatches) blockCodes.push("BLOCKED_EVIDENCE_MISMATCH");
  if (
    quality.minClaimConfidence <
      YOUTUBE_AUTOMATION_POLICY.minClaimConfidence ||
    quality.overallConfidence <
      YOUTUBE_AUTOMATION_POLICY.minOverallConfidence
  ) {
    blockCodes.push("BLOCKED_LOW_CONFIDENCE");
  }
  if (quality.conflicts.length > 0) blockCodes.push("BLOCKED_CONFLICT");
  if (blockCodes.length === 0) {
    return { allowed: true, status: "READY_TO_PUBLISH", blockCodes: [] };
  }
  const reviewOnly = blockCodes.every((code) =>
    [
      "AUTO_PUBLISH_DISABLED",
      "DRY_RUN",
      "MULTI_SOURCE_REQUIRES_REVIEW",
    ].includes(code),
  );
  return {
    allowed: false,
    status: reviewOnly ? "READY_TO_PUBLISH" : "BLOCKED",
    blockCodes,
  };
}
