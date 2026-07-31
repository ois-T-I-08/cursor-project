import { automationHash } from "./idempotency";

export const YOUTUBE_AUTOMATION_POLICY = Object.freeze({
  version: "youtube-quality-v1",
  minClaimConfidence: 0.85,
  minOverallConfidence: 0.85,
  requiredCitationCoverage: 1,
  requiredTimestampCoverage: 1,
  requiredEntityCoverage: 1,
  potentialShortMaxSeconds: 180,
  maxTranscriptSegments: 10_000,
  maxTranscriptBytes: 2_097_152,
  transcriptRetentionDays: 30,
  chunkMaxCharacters: 16_000,
  chunkOverlapSegments: 2,
  maxAttempts: {
    youtube: 3,
    transcript: 2,
    analyzer: 3,
    publish: 1,
  },
  retryBaseSeconds: 30,
  circuitFailureThreshold: 3,
  circuitOpenSeconds: 900,
  automaticPublishScope: "single_source_only",
} as const);

export const YOUTUBE_AUTOMATION_POLICY_HASH = automationHash(
  YOUTUBE_AUTOMATION_POLICY.version,
  YOUTUBE_AUTOMATION_POLICY,
);
