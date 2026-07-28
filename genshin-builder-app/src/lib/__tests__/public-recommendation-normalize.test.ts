import { describe, expect, it } from "vitest";
import {
  buildStructuredPayloadFromEvidences,
  compareGameVersions,
  isSafeYoutubeSourceUrl,
  normalizePublicBuildRecommendation,
  parseInvestmentPriority,
} from "../build-guides/public-recommendation-normalize";
import { publicBuildRecommendationSchema } from "../build-guides/visual-schemas";

const baseSources = [
  {
    videoId: "vid1",
    title: "キャラクター育成解説",
    channelId: "channel1",
    channelTitle: "攻略チャンネル",
    publishedAt: "2026-07-01T10:00:00.000Z",
    reviewedAt: "2026-07-20T10:00:00.000Z",
    gameVersion: "5.8",
    sourceUrl: "https://www.youtube.com/watch?v=vid1",
  },
  {
    videoId: "vid2",
    title: "別解説",
    channelTitle: "別チャンネル",
    sourceUrl: "https://www.youtube.com/watch?v=vid2",
    gameVersion: "5.7",
  },
];

describe("parseInvestmentPriority", () => {
  it("accepts explicit values only", () => {
    expect(parseInvestmentPriority("high")).toBe("high");
    expect(parseInvestmentPriority("medium")).toBe("medium");
    expect(parseInvestmentPriority("low")).toBe("low");
    expect(parseInvestmentPriority(null)).toBeNull();
    expect(parseInvestmentPriority("unknown")).toBeNull();
  });
});

describe("compareGameVersions", () => {
  it("compares numerically not lexicographically", () => {
    expect(compareGameVersions("5.10", "5.9")).toBeGreaterThan(0);
    expect(compareGameVersions("5.8.1", "5.8")).toBeGreaterThan(0);
    expect(compareGameVersions("bad", "5.8")).toBeNull();
  });
});

describe("isSafeYoutubeSourceUrl", () => {
  it.each([
    "https://youtube.com/",
    "https://www.youtube.com/",
    "https://m.youtube.com/",
    "https://youtu.be/",
  ])("allows %s", (url) => {
    expect(isSafeYoutubeSourceUrl(url)).toBe(true);
  });

  it.each([
    "http://www.youtube.com/watch?v=abc",
    "javascript:alert(1)",
    "data:text/plain,hello",
    "file:///tmp/video",
    "ftp://youtube.com/video",
    "https://youtube.com.evil.example/watch?v=abc",
    "https://youtube.example/watch?v=abc",
    "https://user:pass@youtube.com/watch?v=abc",
    "https://www.youtube.com@evil.example/watch?v=abc",
    "https://music.youtube.com/watch?v=abc",
    "https://www.youtube.com./watch?v=abc",
    "https://xn--.com/",
    "",
    "/watch?v=abc",
  ])("rejects %s", (url) => {
    expect(isSafeYoutubeSourceUrl(url)).toBe(false);
  });
});

describe("normalizePublicBuildRecommendation", () => {
  it("normalizes structured weapons and artifact 2+2 with citationId", () => {
    const { data, warnings } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      overallConfidence: 0.9,
      investmentPriority: "high",
      gameVersion: "5.8",
      context: { weaponPreference: "旧文字列は無視" },
      weapons: [
        {
          weaponId: "13501",
          displayName: "護摩の杖",
          rank: 1,
          recommendationLevel: "strongly_recommended",
          reason: "HPと会心",
          conditions: ["HPビルド"],
          source: "vid1",
        },
      ],
      artifactRecommendations: [
        {
          sets: [
            { setId: "15017", pieces: 2 },
            { setId: "15008", pieces: 2 },
          ],
          rank: 2,
          isAlternative: true,
          source: { videoId: "vid2", channelName: "x" },
        },
      ],
      mainStats: [
        {
          slot: "sands",
          primaryStats: ["元素熟知"],
          alternativeStats: ["攻撃力%"],
          condition: "条件",
          citationId: "source-vid1",
        },
      ],
      targets: [{ stat: "critRate", min: 70, unit: "percent" }],
      sources: baseSources,
      evidence: [],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: "2026-07-20T10:00:00.000Z",
    });

    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.investmentPriority).toBe("high");
    expect(parsed.weapons).toHaveLength(1);
    expect(parsed.weapons[0]?.dataOrigin).toBe("structured");
    expect(parsed.weapons[0]?.citationId).toBe("source-vid1");
    expect(parsed.artifactRecommendations[0]?.sets).toEqual([
      { setId: "15017", pieces: 2 },
      { setId: "15008", pieces: 2 },
    ]);
    expect(parsed.artifactRecommendations[0]?.citationId).toBe("source-vid2");
    expect(parsed.mainStats[0]?.stats).toEqual(["元素熟知", "攻撃力%"]);
    expect(parsed.recommendedStats[0]?.valueType).toBe("minimum");
    expect(parsed.context.weaponPreference).toBeUndefined();
    expect(parsed.sources.map((s) => s.id)).toEqual(["source-vid1", "source-vid2"]);
    // バージョン混在時はトップレベル gameVersion を落とす
    expect(parsed.gameVersion).toBeUndefined();
    expect(warnings.some((w) => w.includes("unresolved"))).toBe(false);
  });

  it("accepts alias weaponRecommendations / artifactSets", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      weaponRecommendations: [{ weaponId: "1", displayName: "A" }],
      artifactSets: [{ sets: [{ setId: "15020", pieces: 4 }] }],
      sources: [baseSources[0]],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.weapons[0]?.weaponId).toBe("1");
    expect(parsed.artifactRecommendations[0]?.sets[0]?.pieces).toBe(4);
  });

  it("falls back to legacy weaponPreference only when structured empty", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      context: { weaponPreference: "護摩の杖、匣中滅龍" },
      sources: [baseSources[0]],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.weapons.every((w) => w.dataOrigin === "legacy_preference")).toBe(
      true,
    );
    expect(parsed.weapons.map((w) => w.displayName)).toEqual([
      "護摩の杖",
      "匣中滅龍",
    ]);
  });

  it("excludes evidence_mention and unconfirmed candidates from public output", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      weapons: [
        {
          weaponId: "13501",
          dataOrigin: "evidence_mention",
          adminConfirmed: false,
        },
        {
          weaponId: "15501",
          dataOrigin: "manual",
          adminConfirmed: true,
        },
      ],
      artifactRecommendations: [
        {
          sets: [{ setId: "15020", pieces: 4 }],
          dataOrigin: "evidence_mention",
          adminConfirmed: false,
        },
      ],
      sources: [baseSources[0]],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.weapons.map((w) => w.weaponId)).toEqual(["15501"]);
    expect(parsed.artifactRecommendations).toEqual([]);
  });

  it("does not infer investmentPriority from confidence", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      overallConfidence: 0.99,
      sources: [baseSources[0]],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    expect(data.investmentPriority).toBeUndefined();
  });

  it("keeps candidates when citation unresolved", () => {
    const { data, warnings } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      weapons: [{ weaponId: "1", source: "missing-video" }],
      sources: [baseSources[0]],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.weapons).toHaveLength(1);
    expect(parsed.weapons[0]?.citationId).toBeNull();
    expect(warnings.some((w) => w.includes("unresolved"))).toBe(true);
  });

  it("skips invalid rows without failing whole payload", () => {
    const { data } = normalizePublicBuildRecommendation({
      characterId: "hu-tao",
      weapons: [{}, { weaponId: "ok" }],
      artifactRecommendations: [
        { sets: [] },
        { sets: [{ setId: "15020", pieces: 4 }] },
      ],
      mainStats: [{ slot: "flower", stats: ["HP"] }, { slot: "sands", stats: ["ER"] }],
      targets: [{ stat: "not_a_stat" }, { stat: "er", min: 140, unit: "percent" }],
      sources: [
        { videoId: "bad", title: "x", channelTitle: "y", sourceUrl: "not-a-url" },
        {
          videoId: "evil",
          title: "x",
          channelTitle: "y",
          sourceUrl: "https://youtube.com.evil.example/watch?v=evil",
        },
        baseSources[0],
      ],
      publishedAt: "2026-07-20T10:00:00.000Z",
      updatedAt: "2026-07-20T10:00:00.000Z",
      lastVerifiedAt: null,
    });
    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.weapons.map((w) => w.weaponId)).toEqual(["ok"]);
    expect(parsed.artifactRecommendations).toHaveLength(1);
    expect(parsed.mainStats).toHaveLength(1);
    expect(parsed.targets).toHaveLength(1);
    expect(parsed.sources).toHaveLength(1);
  });
});

describe("buildStructuredPayloadFromEvidences", () => {
  it("stores mentions as pending only without inventing recommendations or 4pc", () => {
    const payload = buildStructuredPayloadFromEvidences([
      {
        videoId: "vid1",
        normalizedPayload: JSON.stringify({
          weaponMentions: [
            {
              exactVisibleText: "護摩の杖",
              normalizedWeaponId: "13501",
              confidence: 0.9,
            },
          ],
          artifactSetMentions: [
            {
              exactVisibleText: "絶縁",
              normalizedArtifactSetId: "15020",
              confidence: 0.8,
            },
          ],
        }),
      },
    ]);
    const parsed = JSON.parse(payload) as {
      weapons: unknown[];
      artifactRecommendations: unknown[];
      structuredReviewStatus: string;
      pendingMentions: {
        weapons: Array<{ weaponId: string; adminConfirmed?: boolean }>;
        artifactSets: Array<{ setId: string; pieces: number | null; needsPieces?: boolean }>;
      };
    };
    expect(parsed.weapons ?? []).toEqual([]);
    expect(parsed.artifactRecommendations ?? []).toEqual([]);
    expect(parsed.structuredReviewStatus).toBe("review_required");
    expect(parsed.pendingMentions.weapons[0]?.weaponId).toBe("13501");
    expect(parsed.pendingMentions.artifactSets[0]?.setId).toBe("15020");
    expect(parsed.pendingMentions.artifactSets[0]?.pieces).toBeNull();
    expect(parsed.pendingMentions.artifactSets[0]?.needsPieces).toBe(true);
  });
});
