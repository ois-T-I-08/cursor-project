import { describe, expect, it } from "vitest";
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
];

describe("public build-recommendation leak guards (visual)", () => {
  it("accepts published visual DTO and rejects internal fields", () => {
    const dto = publicBuildRecommendationSchema.parse({
      characterId: "hu-tao",
      label: "動画内推奨目安",
      status: "published",
      origin: "single_video",
      overallConfidence: 0.7,
      context: {},
      mainStats: [],
      substatPriority: ["er"],
      targets: [{ stat: "er", min: 150, max: 160, unit: "percent" }],
      caveats: ["動画画面内で確認"],
      lastVerifiedAt: "2026-07-15T00:00:00.000Z",
      publishedAt: "2026-07-15T00:00:00.000Z",
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
    const serialized = JSON.stringify(dto);
    for (const key of forbidden) {
      expect(serialized).not.toContain(key);
    }
    expect(() =>
      publicBuildRecommendationSchema.parse({ ...dto, rawAiOutput: "x" }),
    ).toThrow();
  });
});
