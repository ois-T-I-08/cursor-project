import { describe, expect, it } from "vitest";
import {
  normalizeGeminiVisualPayload,
  parseGeminiVisualResult,
} from "../build-guides/normalize-gemini-visual";

describe("normalizeGeminiVisualPayload", () => {
  it("coerces string numbers, timestamps, aliases, and drops bad rows", () => {
    const normalized = normalizeGeminiVisualPayload(
      {
        videoId: "mRzibTGDC6M",
        relevant: true,
        detectedCharacterIds: ["furina", "Furina Name", "bad id"],
        evidences: [
          {
            videoId: "mRzibTGDC6M",
            startSeconds: "2:45",
            endSeconds: "3:00",
            evidenceType: "status_screen",
            targetCharacterIds: ["furina", "フリーナ"],
            visibleTexts: [
              { text: "ER 150%", confidence: "90", category: "value" },
              { text: "", confidence: 0.9, category: "other" },
            ],
            statValues: [
              {
                statKey: "energyRecharge",
                unit: "percent",
                minimum: "150",
                recommended: null,
                maximum: null,
                purpose: "minimum",
                exactVisibleText: "ER 150%",
                confidence: 0.9,
              },
              {
                statKey: "unknownStat",
                unit: "percent",
                purpose: "unknown",
                exactVisibleText: "x",
                confidence: 0.9,
              },
            ],
            confidence: 0.8,
            readable: true,
          },
        ],
        unresolvedEntities: [],
        analysisSummary: "ok",
        extraField: "strip-me",
      },
      "mRzibTGDC6M",
    );

    const parsed = parseGeminiVisualResult(normalized, "mRzibTGDC6M");
    expect(parsed.evidences).toHaveLength(1);
    expect(parsed.evidences[0]?.startSeconds).toBe(165);
    expect(parsed.evidences[0]?.endSeconds).toBe(180);
    expect(parsed.evidences[0]?.evidenceType).toBe("character_status_screen");
    expect(parsed.evidences[0]?.statValues[0]?.statKey).toBe("er");
    expect(parsed.evidences[0]?.statValues[0]?.purpose).toBe(
      "minimum_requirement",
    );
    expect(parsed.evidences[0]?.statValues[0]?.minimum).toBe(150);
    expect(parsed.evidences[0]?.visibleTexts[0]?.confidence).toBe(0.9);
    expect(parsed.detectedCharacterIds).toEqual(["furina"]);
  });

  it("does not throw invalidResult for messy payloads", () => {
    const parsed = parseGeminiVisualResult(
      { hello: "world" },
      "qz3NnOSqucI",
    );
    expect(parsed.videoId).toBe("qz3NnOSqucI");
    expect(parsed.evidences).toEqual([]);
  });

  it("unwraps a single-element array payload from Gemini", () => {
    const parsed = parseGeminiVisualResult(
      [
        {
          videoId: "mh8mw0S1sV0",
          relevant: true,
          detectedCharacterIds: ["columbina"],
          evidences: [
            {
              videoId: "mh8mw0S1sV0",
              startSeconds: 788,
              endSeconds: 808,
              evidenceType: "build_summary_slide",
              targetCharacterIds: ["columbina"],
              visibleTexts: [
                {
                  text: "育成優先度",
                  confidence: 0.95,
                  category: "on_screen_text",
                },
              ],
              statValues: [],
              confidence: 0.95,
              readable: true,
            },
          ],
          unresolvedEntities: [],
          analysisSummary: "ok",
        },
      ],
      "mh8mw0S1sV0",
    );
    expect(parsed.evidences).toHaveLength(1);
    expect(parsed.evidences[0]?.evidenceType).toBe("build_summary_slide");
    expect(parsed.evidences[0]?.visibleTexts[0]?.category).toBe("other");
    expect(parsed.detectedCharacterIds).toEqual(["columbina"]);
  });
});
