import { describe, expect, it } from "vitest";
import {
  actionKey,
  analysisIdempotencyKey,
  automationHash,
  discoveryIdempotencyKey,
  publicationKey,
  transcriptIdentityKey,
} from "@/lib/build-guides/automation/idempotency";
import {
  assertPipelineTransition,
  retryDelayMs,
} from "@/lib/build-guides/automation/state-machine";
import { evaluateDryRunGate } from "@/lib/build-guides/automation/dry-run";
import {
  YOUTUBE_AUTOMATION_POLICY,
  YOUTUBE_AUTOMATION_POLICY_HASH,
} from "@/lib/build-guides/automation/quality-policy";

describe("YouTube automation Phase 1", () => {
  it("uses stable, namespaced idempotency keys", () => {
    expect(automationHash("x", { b: 2, a: 1 })).toBe(
      automationHash("x", { a: 1, b: 2 }),
    );
    const discovery = discoveryIdempotencyKey({
      videoId: "video-1",
      metadataHash: "meta-1",
    });
    const transcript = transcriptIdentityKey({
      videoId: "video-1",
      language: "ja",
      providerId: "test",
      sourceTrackId: "track-1",
      transcriptHash: "transcript-1",
    });
    const analysis = analysisIdempotencyKey({
      videoId: "video-1",
      metadataHash: "meta-1",
      transcriptHash: "transcript-1",
      analyzerVersion: "analyzer-1",
      promptVersion: "prompt-1",
      schemaVersion: "schema-1",
    });
    const publication = publicationKey({
      characterId: "10000002",
      analysisKeys: [analysis],
      policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
      schemaVersion: "schema-1",
    });
    expect(new Set([discovery, transcript, analysis, publication]).size).toBe(4);
    expect(actionKey({ publicationKey: publication, action: "publish" })).toHaveLength(64);
  });

  it("allows only declared state transitions and finite exponential retry", () => {
    expect(() =>
      assertPipelineTransition("DISCOVERED", "METADATA_FETCHED"),
    ).not.toThrow();
    expect(() =>
      assertPipelineTransition("DISCOVERED", "PUBLISHED"),
    ).toThrow("invalidPipelineTransition");
    expect(() =>
      assertPipelineTransition("PUBLISHED", "RETRYABLE_ERROR"),
    ).not.toThrow();
    expect(() =>
      assertPipelineTransition("REVIEW_REQUIRED", "BLOCKED"),
    ).not.toThrow();
    expect(retryDelayMs(1)).toBe(30_000);
    expect(retryDelayMs(3)).toBe(120_000);
    expect(retryDelayMs(20)).toBeLessThanOrEqual(3_600_000);
  });

  it("keeps dry-run publication disabled even when every gate passes", () => {
    const result = evaluateDryRunGate(
      {
        sourceCount: 1,
        channelAllowed: true,
        transcriptAvailable: true,
        schemaValid: true,
        entityCoverage: 1,
        citationCoverage: 1,
        timestampCoverage: 1,
        evidenceMatches: true,
        confidence: 0.95,
        conflicts: [],
      },
      {
        minConfidence: YOUTUBE_AUTOMATION_POLICY.minOverallConfidence,
        entityCoverage: YOUTUBE_AUTOMATION_POLICY.requiredEntityCoverage,
        citationCoverage: YOUTUBE_AUTOMATION_POLICY.requiredCitationCoverage,
        timestampCoverage: YOUTUBE_AUTOMATION_POLICY.requiredTimestampCoverage,
      },
    );
    expect(result).toEqual({
      status: "READY_TO_PUBLISH",
      publishAllowed: false,
      blockCodes: [],
    });
    expect(YOUTUBE_AUTOMATION_POLICY_HASH).toHaveLength(64);
  });

  it.each([
    ["transcript", { transcriptAvailable: false }, "BLOCKED_TRANSCRIPT_UNAVAILABLE"],
    ["entity", { entityCoverage: 0 }, "BLOCKED_UNKNOWN_ENTITY"],
    ["citation", { citationCoverage: 0.9 }, "BLOCKED_UNRESOLVED_CITATION"],
    ["timestamp", { timestampCoverage: 0.5 }, "BLOCKED_TIMESTAMP_INVALID"],
    ["evidence", { evidenceMatches: false }, "BLOCKED_EVIDENCE_MISMATCH"],
    ["confidence", { confidence: 0.84 }, "BLOCKED_LOW_CONFIDENCE"],
  ])("blocks unsafe %s input", (_name, override, expected) => {
    const result = evaluateDryRunGate(
      {
        sourceCount: 1,
        channelAllowed: true,
        transcriptAvailable: true,
        schemaValid: true,
        entityCoverage: 1,
        citationCoverage: 1,
        timestampCoverage: 1,
        evidenceMatches: true,
        confidence: 0.95,
        conflicts: [],
        ...override,
      },
      {
        minConfidence: 0.85,
        entityCoverage: 1,
        citationCoverage: 1,
        timestampCoverage: 1,
      },
    );
    expect(result.status).toBe("BLOCKED");
    expect(result.blockCodes).toContain(expected);
  });
});
