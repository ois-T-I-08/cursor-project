import { describe, expect, it } from "vitest";
import { mergeVisualRecommendationsDeterministic } from "../build-guides/deepseek-visual-merge";

describe("mergeVisualRecommendationsDeterministic", () => {
  it("keeps mainStats and substatPriority from evidences", () => {
    const result = mergeVisualRecommendationsDeterministic({
      characterId: "10000031",
      visualEvidences: [
        {
          evidenceId: "e1",
          videoId: "abcdefghijk",
          startSeconds: 10,
          endSeconds: 20,
          evidenceType: "recommendation_table",
          visibleTexts: ["ER 140%"],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: 140,
              recommended: 140,
              maximum: null,
              purpose: "explicit_recommendation",
            },
          ],
          mainStats: {
            sands: ["元素チャージ効率"],
            goblet: ["攻撃力%"],
            circlet: ["会心率"],
          },
          statPriority: ["critRate", "critDmg", "atk"],
          confidence: 0.9,
        },
      ],
      allowedVideoIds: ["abcdefghijk"],
      allowedCharacterIds: ["10000031"],
      gameDataVersion: "test",
    });

    expect(result.mainStats).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ slot: "sands" }),
        expect.objectContaining({ slot: "goblet" }),
        expect.objectContaining({ slot: "circlet" }),
      ]),
    );
    expect(result.substatPriority).toEqual(["critRate", "critDmg", "atk"]);
    expect(result.targets[0]?.stat).toBe("er");
  });

  it("marks conflicting recommended values", () => {
    const result = mergeVisualRecommendationsDeterministic({
      characterId: "10000031",
      visualEvidences: [
        {
          evidenceId: "e1",
          videoId: "abcdefghijk",
          startSeconds: 1,
          endSeconds: 2,
          evidenceType: "recommendation_table",
          visibleTexts: [],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: null,
              recommended: 140,
              maximum: null,
              purpose: "explicit_recommendation",
            },
          ],
          mainStats: null,
          statPriority: [],
          confidence: 0.9,
        },
        {
          evidenceId: "e2",
          videoId: "abcdefghijk",
          startSeconds: 3,
          endSeconds: 4,
          evidenceType: "recommendation_table",
          visibleTexts: [],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: null,
              recommended: 200,
              maximum: null,
              purpose: "explicit_recommendation",
              condition: "シールド用",
            },
          ],
          mainStats: null,
          statPriority: [],
          confidence: 0.9,
        },
      ],
      allowedVideoIds: ["abcdefghijk"],
      allowedCharacterIds: ["10000031"],
      gameDataVersion: "test",
    });

    expect(result.targets[0]?.conflictingEvidenceIds).toContain("e2");
    expect(result.caveats.some((c) => c.includes("er"))).toBe(true);
  });
});
