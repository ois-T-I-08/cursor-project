import { describe, expect, it } from "vitest";
import { validateVisualAnalysisResult } from "../build-guides/visual-validator";
import type { VideoVisualAnalysisResult } from "../build-guides/visual-schemas";

function baseResult(
  overrides: Partial<VideoVisualAnalysisResult> = {},
): VideoVisualAnalysisResult {
  return {
    videoId: "abcdefghijk",
    relevant: true,
    detectedCharacterIds: ["hu-tao"],
    unresolvedEntities: [],
    analysisSummary: "ok",
    evidences: [
      {
        videoId: "abcdefghijk",
        startSeconds: 120,
        endSeconds: 130,
        evidenceType: "recommendation_table",
        targetCharacterIds: ["hu-tao"],
        visibleTexts: [
          { text: "ER 150～160%", confidence: 0.9, category: "stat_value" },
        ],
        statValues: [
          {
            statKey: "er",
            unit: "percent",
            minimum: 150,
            recommended: 155,
            maximum: 160,
            purpose: "recommended_range",
            exactVisibleText: "ER 150～160%",
            condition: "",
            confidence: 0.9,
          },
        ],
        recommendedMainStats: null,
        statPriority: [],
        weaponMentions: [],
        artifactSetMentions: [],
        visualSummary: "ER table",
        confidence: 0.9,
        readable: true,
        warnings: [],
      },
    ],
    ...overrides,
  };
}

describe("visual validator", () => {
  it("accepts publishable recommendation tables", () => {
    const validated = validateVisualAnalysisResult({
      expectedVideoId: "abcdefghijk",
      durationSeconds: 600,
      allowedCharacterIds: new Set(["hu-tao"]),
      knownCharacterIds: new Set(["hu-tao"]),
      result: baseResult(),
    });
    expect(validated[0]?.validationStatus).toBe("validated");
    expect(validated[0]?.publishableStatValues).toHaveLength(1);
  });

  it("rejects creator current build and damage test purposes", () => {
    const result = baseResult();
    result.evidences[0]!.statValues[0]!.purpose = "creator_current_build";
    result.evidences[0]!.statValues[0]!.exactVisibleText = "ER 180%";
    const validated = validateVisualAnalysisResult({
      expectedVideoId: "abcdefghijk",
      durationSeconds: 600,
      allowedCharacterIds: new Set(["hu-tao"]),
      knownCharacterIds: new Set(["hu-tao"]),
      result,
    });
    expect(validated[0]?.validationStatus).toBe("rejected");
  });

  it("rejects timestamps beyond duration and videoId mismatch", () => {
    expect(() =>
      validateVisualAnalysisResult({
        expectedVideoId: "abcdefghijk",
        durationSeconds: 600,
        allowedCharacterIds: new Set(["hu-tao"]),
        knownCharacterIds: new Set(["hu-tao"]),
        result: baseResult({ videoId: "otherzzzzzz" }),
      }),
    ).toThrow(/videoIdMismatch/);

    const late = baseResult();
    late.evidences[0]!.startSeconds = 900;
    late.evidences[0]!.endSeconds = 910;
    const validated = validateVisualAnalysisResult({
      expectedVideoId: "abcdefghijk",
      durationSeconds: 600,
      allowedCharacterIds: new Set(["hu-tao"]),
      knownCharacterIds: new Set(["hu-tao"]),
      result: late,
    });
    expect(validated[0]?.exclusionCode).toBe("timestampBeyondDuration");
  });

  it("rejects unreadable and low confidence", () => {
    const unread = baseResult();
    unread.evidences[0]!.readable = false;
    unread.evidences[0]!.evidenceType = "unreadable";
    const validated = validateVisualAnalysisResult({
      expectedVideoId: "abcdefghijk",
      durationSeconds: 600,
      allowedCharacterIds: new Set(["hu-tao"]),
      knownCharacterIds: new Set(["hu-tao"]),
      result: unread,
    });
    expect(validated[0]?.exclusionCode).toBe("unreadable");
  });
});
