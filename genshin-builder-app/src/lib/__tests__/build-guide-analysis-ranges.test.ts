import { describe, expect, it } from "vitest";
import {
  AnalysisRangeError,
  normalizeAnalysisRanges,
  timestampWithinRanges,
} from "../build-guides/analysis-ranges";
import { validateVisualAnalysisResult } from "../build-guides/visual-validator";
import type { VideoVisualAnalysisResult } from "../build-guides/visual-schemas";

describe("analysis ranges", () => {
  it("rejects invalid order, overlong, and out-of-duration ranges", () => {
    expect(() =>
      normalizeAnalysisRanges({
        ranges: [{ startSeconds: 20, endSeconds: 10, reason: "bad" }],
        durationSeconds: 100,
        maxRangeSeconds: 60,
        maxRanges: 5,
      }),
    ).toThrow(AnalysisRangeError);

    expect(() =>
      normalizeAnalysisRanges({
        ranges: [{ startSeconds: 0, endSeconds: 200, reason: "long" }],
        durationSeconds: 300,
        maxRangeSeconds: 60,
        maxRanges: 5,
      }),
    ).toThrow(/rangeTooLong/);

    expect(() =>
      normalizeAnalysisRanges({
        ranges: [{ startSeconds: 90, endSeconds: 110, reason: "late" }],
        durationSeconds: 100,
        maxRangeSeconds: 60,
        maxRanges: 5,
      }),
    ).toThrow(/rangeBeyondDuration/);
  });

  it("accepts valid ranges with start < end", () => {
    const ranges = normalizeAnalysisRanges({
      ranges: [{ startSeconds: 120.2, endSeconds: 149.8, reason: "table" }],
      durationSeconds: 600,
      maxRangeSeconds: 180,
      maxRanges: 5,
    });
    expect(ranges[0]).toMatchObject({
      startSeconds: 120,
      endSeconds: 150,
      reason: "table",
    });
    expect(timestampWithinRanges(125, 130, ranges)).toBe(true);
    expect(timestampWithinRanges(0, 5, ranges)).toBe(false);
  });

  it("rejects evidence timestamps outside requested clip windows", () => {
    const result: VideoVisualAnalysisResult = {
      videoId: "abcdefghijk",
      relevant: true,
      detectedCharacterIds: ["hu-tao"],
      unresolvedEntities: [],
      analysisSummary: "x",
      evidences: [
        {
          videoId: "abcdefghijk",
          startSeconds: 10,
          endSeconds: 20,
          evidenceType: "recommendation_table",
          targetCharacterIds: ["hu-tao"],
          visibleTexts: [
            { text: "ER 150%", confidence: 0.9, category: "stat_value" },
          ],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: 150,
              recommended: null,
              maximum: null,
              purpose: "minimum_requirement",
              exactVisibleText: "ER 150%",
              condition: "",
              confidence: 0.9,
            },
          ],
          recommendedMainStats: null,
          statPriority: [],
          weaponMentions: [],
          artifactSetMentions: [],
          visualSummary: "outside",
          confidence: 0.9,
          readable: true,
          warnings: [],
        },
      ],
    };

    const validated = validateVisualAnalysisResult({
      expectedVideoId: "abcdefghijk",
      durationSeconds: 600,
      allowedCharacterIds: new Set(["hu-tao"]),
      knownCharacterIds: new Set(["hu-tao"]),
      result,
      allowedWindows: [{ startSeconds: 120, endSeconds: 150 }],
    });
    expect(validated[0]?.exclusionCode).toBe("timestampOutsideRequestedRange");
  });
});
