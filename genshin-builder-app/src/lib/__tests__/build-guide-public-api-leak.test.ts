import { describe, expect, it } from "vitest";
import { normalizePublicBuildRecommendation } from "../build-guides/public-recommendation-normalize";
import { publicBuildRecommendationSchema } from "../build-guides/visual-schemas";

const forbidden = [
  "rawAiOutput",
  "adminNotes",
  "tokenUsage",
  "requestHash",
  "GEMINI_API_KEY",
  "DEEPSEEK_API_KEY",
  "system_instruction",
  "transcript",
  "adminWorkingDraft",
  "pendingMentions",
  "structuredReviewStatus",
  "SECRET_ADMIN",
];

describe("public build-recommendation leak guards (visual)", () => {
  it("accepts published visual DTO and rejects internal fields", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      origin: "single_video",
      overallConfidence: 0.7,
      context: {},
      mainStats: [],
      substatPriority: ["er"],
      targets: [{ stat: "er", min: 150, max: 160, unit: "percent" }],
      caveats: ["動画画面内で確認"],
      lastVerifiedAt: "2026-07-15T00:00:00.000Z",
      publishedAt: "2026-07-15T00:00:00.000Z",
      updatedAt: "2026-07-15T00:00:00.000Z",
      structured: {
        adminWorkingDraft: {
          adminNotes: "SECRET_ADMIN",
          structured: {
            weapons: [{ weaponId: "x", dataOrigin: "evidence_mention" }],
          },
        },
        pendingMentions: { weapons: [{ weaponId: "x" }], artifactSets: [] },
        structuredReviewStatus: "review_required",
      },
      sources: [
        {
          videoId: "abcdefghijk",
          title: "guide",
          channelTitle: "channel",
          sourceUrl: "https://www.youtube.com/watch?v=abcdefghijk",
        },
      ],
      evidence: [
        {
          fieldPath: "visual",
          exactVisibleText: "ER 150～160%",
          startSeconds: 120,
          endSeconds: 130,
          videoId: "abcdefghijk",
        },
      ],
    });

    const dto = publicBuildRecommendationSchema.parse(data);
    const serialized = JSON.stringify(dto);
    for (const key of forbidden) {
      expect(serialized).not.toContain(key);
    }
    expect(dto.schemaVersion).toBe(1);
    expect(dto.weapons).toEqual([]);
    expect(dto.artifactRecommendations).toEqual([]);
    expect(() =>
      publicBuildRecommendationSchema.parse({ ...dto, rawAiOutput: "x" }),
    ).toThrow();
  });
});
