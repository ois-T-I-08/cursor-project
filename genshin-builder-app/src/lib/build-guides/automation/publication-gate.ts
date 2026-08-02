import type { YoutubeAutomationFlags } from "./feature-flags";
import { z } from "zod";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

export const automaticPublicationQualitySchema = z
  .object({
    channelAllowed: z.boolean(),
    videoPublic: z.boolean(),
    transcriptAvailable: z.boolean(),
    schemaValid: z.boolean(),
    entityCoverage: z.number().min(0).max(1),
    citationCoverage: z.number().min(0).max(1),
    timestampCoverage: z.number().min(0).max(1),
    evidenceMatches: z.boolean(),
    minClaimConfidence: z.number().min(0).max(1),
    overallConfidence: z.number().min(0).max(1),
    conflicts: z.array(z.string().max(200)).max(100),
  })
  .strict();

export type AutomaticPublicationQuality = Readonly<
  Omit<z.infer<typeof automaticPublicationQualitySchema>, "conflicts"> & {
    conflicts: readonly string[];
  }
>;

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
  sourceCount: number;
  quality: AutomaticPublicationQuality;
}): AutomaticPublicationGate {
  const blockCodes: string[] = [];
  const { quality } = input;
  if (!input.flags.enabled || !input.flags.autoPublishEnabled) {
    blockCodes.push("AUTO_PUBLISH_DISABLED");
  }
  if (input.dryRun) blockCodes.push("DRY_RUN");
  if (input.emergencyStopped) blockCodes.push("EMERGENCY_STOPPED");
  if (input.sourceCount !== 1) {
    blockCodes.push(
      input.sourceCount > 1
        ? "MULTI_SOURCE_REVIEW_REQUIRED"
        : "SOURCE_REQUIRED",
    );
  }
  if (!quality.channelAllowed) blockCodes.push("CHANNEL_NOT_ALLOWED");
  if (!quality.videoPublic) blockCodes.push("VIDEO_NOT_PUBLIC");
  if (!quality.transcriptAvailable) {
    blockCodes.push("BLOCKED_TRANSCRIPT_UNAVAILABLE");
  }
  if (!quality.schemaValid) blockCodes.push("BLOCKED_INVALID_ANALYSIS");
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
      "MULTI_SOURCE_REVIEW_REQUIRED",
    ].includes(code),
  );
  return {
    allowed: false,
    status: reviewOnly ? "READY_TO_PUBLISH" : "BLOCKED",
    blockCodes,
  };
}
