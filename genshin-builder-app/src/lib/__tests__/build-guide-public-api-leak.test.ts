import { describe, expect, it } from "vitest";
import {
  publicBuildRecommendationSchema,
  validatedGuidePayloadSchema,
} from "../build-guides/schemas";

const forbiddenKeys = [
  "rawAiOutput",
  "adminNotes",
  "transcript",
  "transcriptHash",
  "metadataHash",
  "usagePayload",
  "prompt_tokens",
  "systemPrompt",
  "apiKey",
  "YOUTUBE_API_KEY",
  "BUILD_GUIDE_ADMIN_SECRET",
  "actorHash",
  "normalizedTranscript",
  "chunkText",
];

describe("public build-recommendation leak guards", () => {
  it("public DTO schema rejects internal fields (strict)", () => {
    const base = {
      characterId: "hu-tao",
      label: "動画内推奨目安" as const,
      status: "published" as const,
      origin: "single_video" as const,
      overallConfidence: 0.7,
      context: { role: "dps" },
      mainStats: [],
      substatPriority: ["critRate" as const],
      targets: [{ stat: "critRate" as const, recommended: 70, unit: "percent" as const }],
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
    };

    const ok = publicBuildRecommendationSchema.parse(base);
    const serialized = JSON.stringify(ok);
    for (const key of forbiddenKeys) {
      expect(serialized).not.toContain(key);
    }

    expect(() =>
      publicBuildRecommendationSchema.parse({
        ...base,
        rawAiOutput: "SECRET",
      }),
    ).toThrow();
    expect(() =>
      publicBuildRecommendationSchema.parse({
        ...base,
        adminNotes: "internal",
      }),
    ).toThrow();
    expect(() =>
      publicBuildRecommendationSchema.parse({
        ...base,
        transcriptHash: "abc",
      }),
    ).toThrow();
  });

  it("rejects negative and absurdly large stat numbers", () => {
    expect(() =>
      validatedGuidePayloadSchema.parse({
        characterId: "hu-tao",
        context: {},
        mainStats: [],
        substatPriority: [],
        targets: [{ stat: "critRate", recommended: -1, inferred: false }],
        overallConfidence: 0.5,
        caveats: [],
        unresolvedEntities: [],
      }),
    ).toThrow();
    expect(() =>
      validatedGuidePayloadSchema.parse({
        characterId: "hu-tao",
        context: {},
        mainStats: [],
        substatPriority: [],
        targets: [{ stat: "hp", recommended: 9_999_999, inferred: false }],
        overallConfidence: 0.5,
        caveats: [],
        unresolvedEntities: [],
      }),
    ).toThrow();
  });

  it("only published status is representable in public schema", () => {
    expect(() =>
      publicBuildRecommendationSchema.parse({
        characterId: "hu-tao",
        label: "動画内推奨目安",
        status: "pending_review",
        origin: "single_video",
        overallConfidence: 0.7,
        context: {},
        mainStats: [],
        substatPriority: [],
        targets: [],
        caveats: [],
        lastVerifiedAt: null,
        publishedAt: null,
        sources: [],
        evidence: [],
      }),
    ).toThrow();
  });
});
