import { describe, expect, it } from "vitest";
import { publicBuildRecommendationSchema } from "../build-guides/schemas";

describe("public build recommendation DTO", () => {
  it("accepts public fields and rejects raw AI / transcript keys when stripped", () => {
    const dto = publicBuildRecommendationSchema.parse({
      characterId: "hu-tao",
      label: "動画内推奨目安",
      status: "published",
      origin: "single_video",
      overallConfidence: 0.7,
      context: { role: "dps" },
      mainStats: [],
      substatPriority: ["critRate"],
      targets: [{ stat: "critRate", recommended: 70, unit: "percent" }],
      caveats: ["編成バフは含みません"],
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
          fieldPath: "targets.critRate",
          snippet: "会心率70",
          videoId: "abcdefghijk",
        },
      ],
    });
    expect(dto.label).toBe("動画内推奨目安");
    expect(JSON.stringify(dto)).not.toContain("rawAiOutput");
    expect(JSON.stringify(dto)).not.toContain("adminNotes");
    expect(JSON.stringify(dto)).not.toContain("transcript");
  });
});
