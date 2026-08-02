import { describe, expect, it } from "vitest";
import { mergeVisualRecommendationsDeterministic } from "../build-guides/deepseek-visual-merge";

describe("visual recommendation merge", () => {
  it("merges same ER range from multiple videos as supporting evidence", () => {
    const merged = mergeVisualRecommendationsDeterministic({
      characterId: "furina",
      visualEvidences: [
        {
          evidenceId: "e1",
          videoId: "videoaaaaaa",
          startSeconds: 530,
          endSeconds: 540,
          evidenceType: "recommendation_table",
          visibleTexts: ["ER 150～160%"],
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
          mainStats: null,
          statPriority: [],
          confidence: 0.9,
        },
        {
          evidenceId: "e2",
          videoId: "videobbbbbb",
          startSeconds: 374,
          endSeconds: 380,
          evidenceType: "on_screen_text",
          visibleTexts: ["元素チャージ 150%以上"],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: 150,
              recommended: null,
              maximum: null,
              purpose: "minimum_requirement",
              exactVisibleText: "元素チャージ 150%以上",
              condition: "",
              confidence: 0.85,
            },
          ],
          mainStats: null,
          statPriority: [],
          confidence: 0.85,
        },
      ],
      allowedVideoIds: ["videoaaaaaa", "videobbbbbb"],
      allowedCharacterIds: ["furina"],
      gameDataVersion: "test",
    });

    const er = merged.targets.find((t) => t.stat === "er");
    expect(er).toBeTruthy();
    expect(er?.primaryEvidenceIds.length).toBeGreaterThan(0);
    expect(
      [...(er?.primaryEvidenceIds ?? []), ...(er?.supportingEvidenceIds ?? [])],
    ).toEqual(expect.arrayContaining(["e1", "e2"]));
  });

  it("does not emit targets for creator_current_build or damage_test_build", () => {
    const merged = mergeVisualRecommendationsDeterministic({
      characterId: "furina",
      visualEvidences: [
        {
          evidenceId: "bad1",
          videoId: "videoaaaaaa",
          startSeconds: 10,
          endSeconds: 20,
          evidenceType: "character_status_screen",
          visibleTexts: ["ER 210%"],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: null,
              recommended: 210,
              maximum: null,
              purpose: "creator_current_build",
              exactVisibleText: "ER 210%",
              condition: "",
              confidence: 0.99,
            },
          ],
          mainStats: null,
          statPriority: [],
          confidence: 0.99,
        },
        {
          evidenceId: "bad2",
          videoId: "videoaaaaaa",
          startSeconds: 30,
          endSeconds: 40,
          evidenceType: "comparison_table",
          visibleTexts: ["ER 120%"],
          statValues: [
            {
              statKey: "er",
              unit: "percent",
              minimum: null,
              recommended: 120,
              maximum: null,
              purpose: "damage_test_build",
              exactVisibleText: "ER 120%",
              condition: "",
              confidence: 0.99,
            },
          ],
          mainStats: null,
          statPriority: [],
          confidence: 0.99,
        },
      ],
      allowedVideoIds: ["videoaaaaaa"],
      allowedCharacterIds: ["furina"],
      gameDataVersion: "test",
    });
    expect(merged.targets).toHaveLength(0);
  });
});
