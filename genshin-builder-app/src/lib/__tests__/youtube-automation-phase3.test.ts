import { describe, expect, it } from "vitest";
import {
  AutomaticSnapshotError,
  buildAutomaticRecommendationSnapshot,
} from "@/lib/build-guides/automation/automatic-snapshot";
import { evaluateAutomaticPublicationGate } from "@/lib/build-guides/automation/publication-gate";
import type { ValidatedTranscriptClaim } from "@/lib/build-guides/automation/analysis-schema";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import { readYoutubeAutomationControl } from "@/lib/build-guides/automation/automation-control";

const enabledFlags: YoutubeAutomationFlags = {
  enabled: true,
  guideEnabled: true,
  discoveryEnabled: true,
  transcriptEnabled: true,
  analysisEnabled: true,
  geminiAnalysisEnabled: true,
  deepseekAnalysisEnabled: false,
  autoPublishEnabled: true,
  maintenanceEnabled: true,
};

const quality = {
  channelAllowed: true,
  videoPublic: true,
  transcriptAvailable: true,
  schemaValid: true,
  entityCoverage: 1,
  citationCoverage: 1,
  timestampCoverage: 1,
  evidenceMatches: true,
  minClaimConfidence: 0.95,
  overallConfidence: 0.96,
  conflicts: [],
} as const;

describe("YouTube automation Phase 3", () => {
  it("allows only explicit, non-dry-run, single-source automatic publication", () => {
    expect(
      evaluateAutomaticPublicationGate({
        flags: enabledFlags,
        dryRun: false,
        emergencyStopped: false,
        sourceCount: 1,
        quality,
      }),
    ).toEqual({
      allowed: true,
      status: "READY_TO_PUBLISH",
      blockCodes: [],
    });
    expect(
      evaluateAutomaticPublicationGate({
        flags: { ...enabledFlags, autoPublishEnabled: false },
        dryRun: false,
        emergencyStopped: false,
        sourceCount: 1,
        quality,
      }),
    ).toMatchObject({
      allowed: false,
      status: "READY_TO_PUBLISH",
      blockCodes: ["AUTO_PUBLISH_DISABLED"],
    });
    expect(
      evaluateAutomaticPublicationGate({
        flags: enabledFlags,
        dryRun: false,
        emergencyStopped: false,
        sourceCount: 2,
        quality,
      }),
    ).toMatchObject({
      allowed: false,
      status: "READY_TO_PUBLISH",
      blockCodes: ["MULTI_SOURCE_REVIEW_REQUIRED"],
    });
  });

  it("fails closed for emergency stop, unsafe confidence, or conflicts", () => {
    const result = evaluateAutomaticPublicationGate({
      flags: enabledFlags,
      dryRun: false,
      emergencyStopped: true,
      sourceCount: 1,
      quality: {
        ...quality,
        minClaimConfidence: 0.5,
        conflicts: ["fixture-conflict"],
      },
    });
    expect(result).toMatchObject({ allowed: false, status: "BLOCKED" });
    expect(result.blockCodes).toEqual(
      expect.arrayContaining([
        "EMERGENCY_STOPPED",
        "BLOCKED_LOW_CONFIDENCE",
        "BLOCKED_CONFLICT",
      ]),
    );
  });

  it("builds a public snapshot without copying transcript evidence text", () => {
    const snapshot = buildAutomaticRecommendationSnapshot({
      characterId: "raiden-shogun",
      videoId: "phase3Video",
      claims: claims(),
      overallConfidence: 0.96,
      publishedContentUpdatedAt: new Date("2026-07-31T00:00:00.000Z"),
    });
    const serialized = JSON.stringify(snapshot);
    expect(serialized).not.toContain("字幕だけに存在する原文");
    expect(snapshot.structuredPayload).toMatchObject({
      automationSourceVideoId: "phase3Video",
      weapons: [{ weaponId: "the-catch" }],
      recommendedStats: [{ stat: "er", valueType: "range" }],
    });
    expect(snapshot.evidenceStartSeconds).toBe(10);
    expect(snapshot.evidenceEndSeconds).toBe(25);
  });

  it("blocks snapshot creation when a mapped stat is unknown", () => {
    const invalid = claims().map((claim) =>
      claim.kind === "target" ? { ...claim, entityId: "unknown-stat" } : claim,
    );
    expect(() =>
      buildAutomaticRecommendationSnapshot({
        characterId: "raiden-shogun",
        videoId: "phase3Video",
        claims: invalid,
        overallConfidence: 0.96,
        publishedContentUpdatedAt: new Date(),
      }),
    ).toThrow(AutomaticSnapshotError);
  });

  it("fails closed when the control database read fails", async () => {
    const control = await readYoutubeAutomationControl({
      guideAutomationControl: {
        findUnique: async () => {
          throw new Error("database unavailable");
        },
      },
    } as never);
    expect(control).toEqual({
      emergencyStopped: true,
      reason: "CONTROL_READ_FAILED",
      version: -1,
    });
  });
});

function claims(): ValidatedTranscriptClaim[] {
  return [
    {
      claimId: "weapon",
      kind: "weapon",
      entityId: "the-catch",
      slot: null,
      value: "漁獲",
      condition: "",
      confidence: 0.96,
      evidenceSegmentIds: ["segment-1"],
      evidenceText: "字幕だけに存在する原文",
      startSeconds: 10,
      endSeconds: 15,
    },
    {
      claimId: "target",
      kind: "target",
      entityId: "er",
      slot: null,
      value: "220%〜250%",
      condition: "",
      confidence: 0.95,
      evidenceSegmentIds: ["segment-2"],
      evidenceText: "字幕だけに存在する原文",
      startSeconds: 20,
      endSeconds: 25,
    },
  ];
}
