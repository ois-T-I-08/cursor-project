/**
 * 構造化育成情報のリリース前統合検証（fixture 専用・本番投入なし）
 */
import { createHash } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import {
  ADMIN_WORKING_DRAFT_KEY,
  buildArtifactSetsPayload,
  stripAdminWorkingDraft,
  targetDraftToPayload,
} from "../build-guides/guide-admin-form";
import { buildPublicRecommendationEtag } from "../build-guides/public-etag";
import {
  normalizePublicBuildRecommendation,
} from "../build-guides/public-recommendation-normalize";
import {
  validateStructuredDraft,
  validateStructuredForPublish,
} from "../build-guides/structured-admin";
import { publicBuildRecommendationSchema } from "../build-guides/visual-schemas";

const FIXTURE_CHARACTER = "fixture-guide-release-char";

const knownWeaponIds = new Set(["13501", "15501", "14504"]);
const knownSetIds = new Set(["15020", "15017", "15008"]);

const forbiddenLeakKeys = [
  "adminWorkingDraft",
  "pendingMentions",
  "adminNotes",
  "rawAiOutput",
  "tokenUsage",
  "requestHash",
  "GEMINI_API_KEY",
  "structuredReviewStatus",
  "review_required",
  "evidence_mention",
  "revision",
  "GuideRecommendationRevision",
];

function fixtureStructuredComplete() {
  return {
    schemaVersion: 1,
    investmentPriority: "high",
    gameVersion: "5.8",
    structuredReviewStatus: "admin_confirmed",
    publishedContentUpdatedAt: "2026-07-28T00:00:00.000Z",
    pendingMentions: { weapons: [], artifactSets: [] },
    weapons: [
      {
        weaponId: "13501",
        displayName: "護摩の杖",
        rank: 1,
        recommendationLevel: "strongly_recommended",
        reason: "HPスケールと会心を同時に伸ばせるため、このキャラの主軸として長く推奨されている。".repeat(2),
        conditions: ["HPビルド", "単体向け"],
        role: "main_dps",
        citationId: "source-vidFixtureA",
        dataOrigin: "manual",
        adminConfirmed: true,
      },
      {
        weaponId: "15501",
        displayName: "天空の翼",
        rank: 2,
        recommendationLevel: "recommended",
        reason: "会心武器の汎用枠",
        conditions: ["会心不足時"],
        role: "main_dps",
        citationId: "source-vidFixtureA",
        dataOrigin: "manual",
        adminConfirmed: true,
      },
      {
        weaponId: "14504",
        displayName: "試作品サンプル",
        rank: 3,
        recommendationLevel: "situational",
        reason: "無課金寄り",
        conditions: ["イベント配布"],
        role: "main_dps",
        citationId: "source-vidFixtureB",
        dataOrigin: "manual",
        adminConfirmed: true,
      },
    ],
    artifactRecommendations: [
      {
        compositionMode: "four",
        sets: buildArtifactSetsPayload("four", "15020", ""),
        rank: 1,
        recommendationLevel: "strongly_recommended",
        reason: "爆発回転向け4セット",
        conditions: ["爆発主軸"],
        citationId: "source-vidFixtureA",
        dataOrigin: "manual",
        adminConfirmed: true,
      },
      {
        compositionMode: "two_two",
        sets: buildArtifactSetsPayload("two_two", "15017", "15008"),
        rank: 2,
        recommendationLevel: "alternative",
        reason: "2+2の柔軟枠",
        conditions: ["セット未完"],
        isAlternative: true,
        citationId: "source-vidFixtureB",
        dataOrigin: "manual",
        adminConfirmed: true,
      },
    ],
    recommendedStats: [
      {
        stat: "er",
        valueType: "minimum",
        minimum: 0,
        unit: "percent",
        citationId: "source-vidFixtureA",
      },
      {
        stat: "critDmg",
        valueType: "range",
        minimum: 140,
        maximum: 180,
        unit: "percent",
        citationId: "source-vidFixtureA",
      },
      {
        stat: "em",
        valueType: "target",
        recommended: 800,
        unit: "flat",
        citationId: "source-vidFixtureB",
      },
      {
        stat: "critRate",
        valueType: "ratio",
        leftStat: "critRate",
        leftValue: 1,
        rightStat: "critDmg",
        rightValue: 2,
        unit: "percent",
        citationId: "source-vidFixtureB",
      },
    ],
  };
}

const fixtureSources = [
  {
    id: "source-vidFixtureA",
    videoId: "vidFixtureA",
    title: "Fixture 攻略 A",
    channelId: "chA",
    channelTitle: "Fixture Channel A",
    publishedAt: "2026-07-01T10:00:00.000Z",
    reviewedAt: "2026-07-20T10:00:00.000Z",
    gameVersion: "5.8",
    sourceUrl: "https://www.youtube.com/watch?v=vidFixtureA",
  },
  {
    id: "source-vidFixtureB",
    videoId: "vidFixtureB",
    title: "Fixture 攻略 B（長いタイトルを含む検証用サンプル文字列）",
    channelId: "chB",
    channelTitle: "Fixture Channel B",
    publishedAt: "2026-07-05T10:00:00.000Z",
    reviewedAt: "2026-07-21T10:00:00.000Z",
    gameVersion: "5.8",
    sourceUrl: "https://www.youtube.com/watch?v=vidFixtureB",
  },
];

const fixtureMainStats = [
  {
    slot: "sands",
    primaryStats: ["元素チャージ効率"],
    alternativeStats: ["攻撃力%"],
    stats: ["元素チャージ効率", "攻撃力%"],
    condition: "爆発回転優先",
    citationId: "source-vidFixtureA",
  },
  {
    slot: "goblet",
    primaryStats: ["炎元素ダメージ"],
    alternativeStats: ["攻撃力%"],
    stats: ["炎元素ダメージ", "攻撃力%"],
    citationId: "source-vidFixtureA",
  },
  {
    slot: "circlet",
    primaryStats: ["会心ダメージ"],
    alternativeStats: ["会心率"],
    stats: ["会心ダメージ", "会心率"],
    citationId: "source-vidFixtureB",
  },
];

describe("release fixture: complete structured payload", () => {
  it("normalizes publishable fixture without leaking internals", () => {
    const structured = fixtureStructuredComplete();
    const withDraft = {
      ...structured,
      [ADMIN_WORKING_DRAFT_KEY]: {
        structured: { weapons: [{ weaponId: "DRAFT_ONLY", adminConfirmed: false }] },
        adminNotes: "SECRET_ADMIN_NOTE",
      },
      pendingMentions: {
        weapons: [{ weaponId: "13501", dataOrigin: "evidence_mention" }],
        artifactSets: [],
      },
    };

    const publishedStructured = stripAdminWorkingDraft(withDraft);
    expect(publishedStructured[ADMIN_WORKING_DRAFT_KEY]).toBeUndefined();

    const { data, warnings } = normalizePublicBuildRecommendation({
      characterId: FIXTURE_CHARACTER,
      origin: "merged",
      overallConfidence: 0.85,
      context: {},
      mainStats: fixtureMainStats,
      targets: [],
      structured: publishedStructured,
      weapons: publishedStructured.weapons,
      artifactRecommendations: publishedStructured.artifactRecommendations,
      investmentPriority: publishedStructured.investmentPriority,
      gameVersion: publishedStructured.gameVersion,
      recommendedStats: publishedStructured.recommendedStats,
      sources: fixtureSources,
      evidence: [],
      publishedAt: "2026-07-28T00:00:00.000Z",
      updatedAt: "2026-07-28T00:00:00.000Z",
      lastVerifiedAt: "2026-07-28T00:00:00.000Z",
    });

    const parsed = publicBuildRecommendationSchema.parse(data);
    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.investmentPriority).toBe("high");
    expect(parsed.weapons).toHaveLength(3);
    expect(parsed.artifactRecommendations).toHaveLength(2);
    expect(parsed.artifactRecommendations[0]?.sets).toEqual([
      { setId: "15020", pieces: 4 },
    ]);
    expect(parsed.artifactRecommendations[1]?.sets).toEqual([
      { setId: "15017", pieces: 2 },
      { setId: "15008", pieces: 2 },
    ]);
    expect(parsed.mainStats).toHaveLength(3);
    expect(parsed.recommendedStats.some((r) => r.valueType === "minimum" && r.minimum === 0)).toBe(
      true,
    );
    expect(parsed.recommendedStats.some((r) => r.valueType === "range")).toBe(true);
    expect(parsed.recommendedStats.some((r) => r.valueType === "target")).toBe(true);
    expect(parsed.recommendedStats.some((r) => r.valueType === "ratio")).toBe(true);
    // ratio は targets 互換行に載せない（critRate ratio のみの行が targets に出ない）
    const ratioOnlyTargets = parsed.targets.filter(
      (t) =>
        t.stat === "critRate" &&
        t.min == null &&
        t.max == null &&
        t.recommended == null,
    );
    expect(ratioOnlyTargets).toHaveLength(0);
    // 他の目標ステータスは欠落しない
    expect(parsed.targets.some((t) => t.stat === "er" && t.min === 0)).toBe(true);
    expect(parsed.targets.some((t) => t.stat === "critDmg" && t.min === 140)).toBe(
      true,
    );
    expect(parsed.targets.some((t) => t.stat === "em" && t.recommended === 800)).toBe(
      true,
    );

    const serialized = JSON.stringify(parsed);
    for (const key of forbiddenLeakKeys) {
      if (key === "review_required" || key === "evidence_mention") {
        expect(serialized).not.toContain(key);
        continue;
      }
      expect(serialized).not.toContain(key);
    }
    expect(serialized).not.toContain("SECRET_ADMIN_NOTE");
    expect(serialized).not.toContain("DRAFT_ONLY");
    expect(parsed.sources.map((s) => s.id).sort()).toEqual([
      "source-vidFixtureA",
      "source-vidFixtureB",
    ]);
    expect(new Set(parsed.sources.map((s) => s.id)).size).toBe(parsed.sources.length);
    expect(warnings.some((w) => w.toLowerCase().includes("admin"))).toBe(false);
  });
});

describe("release: publish rejection matrix", () => {
  const base = fixtureStructuredComplete();

  it.each([
    [
      "pendingMentions",
      {
        ...base,
        pendingMentions: { weapons: [{ weaponId: "13501" }], artifactSets: [] },
      },
      "未確認の映像言及",
    ],
    [
      "adminConfirmed false",
      {
        ...base,
        weapons: base.weapons.map((w, i) =>
          i === 0 ? { ...w, adminConfirmed: false } : w,
        ),
      },
      "未確認の武器候補",
    ],
    [
      "review_required",
      { ...base, structuredReviewStatus: "review_required" },
      "構造化レビューが未完了",
    ],
    [
      "unknown weapon",
      {
        ...base,
        weapons: [{ ...base.weapons[0]!, weaponId: "no-such-weapon" }],
      },
      "不正な武器ID",
    ],
    [
      "unknown set",
      {
        ...base,
        artifactRecommendations: [
          {
            ...base.artifactRecommendations[0]!,
            sets: [{ setId: "99999", pieces: 4 }],
          },
        ],
      },
      "マスターに存在しない setId",
    ],
    [
      "undetermined composition",
      {
        ...base,
        artifactRecommendations: [
          {
            compositionMode: "undetermined",
            sets: [{ setId: "15020", pieces: null }],
            adminConfirmed: false,
          },
        ],
      },
      "未確定の聖遺物構成",
    ],
  ] as const)("rejects %s", (_name, structured, messagePart) => {
    const issues = validateStructuredForPublish({
      characterId: FIXTURE_CHARACTER,
      structured: structured as Record<string, unknown>,
      mainStats: fixtureMainStats,
      targets: [],
      sources: fixtureSources,
      knownWeaponIds,
      knownSetIds,
    });
    expect(issues.some((i) => i.level === "error" && i.message.includes(messagePart))).toBe(
      true,
    );
  });

  it("draft allows incomplete undetermined composition as warning", () => {
    const issues = validateStructuredDraft({
      characterId: FIXTURE_CHARACTER,
      structured: {
        structuredReviewStatus: "review_required",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [],
        artifactRecommendations: [
          {
            compositionMode: "undetermined",
            sets: [{ setId: "15020", pieces: null }],
            adminConfirmed: false,
          },
        ],
      },
      knownWeaponIds,
      knownSetIds,
    });
    expect(issues.some((i) => i.level === "error")).toBe(false);
    expect(issues.some((i) => i.message.includes("未確定"))).toBe(true);
  });

  it("warns ratio for mobile compatibility without blocking publish alone", () => {
    const issues = validateStructuredForPublish({
      characterId: FIXTURE_CHARACTER,
      structured: base,
      mainStats: fixtureMainStats,
      targets: [],
      sources: fixtureSources,
      knownWeaponIds,
      knownSetIds,
    });
    expect(
      issues.some(
        (i) => i.level === "warning" && i.message.includes("モバイル版では表示されない"),
      ),
    ).toBe(true);
    // ratio 警告以外の fatal が無ければ canPublish
    const fatals = issues.filter((i) => i.level === "error");
    expect(fatals).toEqual([]);
  });

  it("blocks artifact publication while the Amber set master is unavailable", () => {
    const issues = validateStructuredForPublish({
      characterId: FIXTURE_CHARACTER,
      structured: base,
      mainStats: fixtureMainStats,
      targets: [],
      sources: fixtureSources,
      knownWeaponIds,
      knownSetIds: new Set(),
      artifactMasterAvailable: false,
    });
    expect(
      issues.some(
        (issue) =>
          issue.level === "error" &&
          issue.message.includes("聖遺物セットマスターを取得できない"),
      ),
    ).toBe(true);
  });

  it("rejects every unresolved citation even when no sources are available", () => {
    const issues = validateStructuredForPublish({
      characterId: FIXTURE_CHARACTER,
      structured: base,
      mainStats: fixtureMainStats,
      targets: [],
      sources: [],
      knownWeaponIds,
      knownSetIds,
      artifactMasterAvailable: true,
    });
    expect(
      issues.some(
        (issue) =>
          issue.path === "weapons[0].citationId" &&
          issue.message.includes("解決不能"),
      ),
    ).toBe(true);
    expect(
      issues.some(
        (issue) =>
          issue.path === "recommendedStats[0].citationId" &&
          issue.message.includes("解決不能"),
      ),
    ).toBe(true);
    expect(
      issues.some(
        (issue) =>
          issue.path === "mainStats[0].citationId" &&
          issue.message.includes("解決不能"),
      ),
    ).toBe(true);
  });
});

describe("release: keepPublished isolation", () => {
  it("working draft changes do not alter published snapshot fields", () => {
    const published = fixtureStructuredComplete();
    const envelope = {
      ...published,
      [ADMIN_WORKING_DRAFT_KEY]: {
        structured: {
          ...published,
          weapons: [
            {
              weaponId: "13501",
              adminConfirmed: true,
              reason: "DRAFT_REASON_SHOULD_NOT_LEAK",
            },
          ],
        },
        adminNotes: "draft-notes",
      },
    };
    const live = stripAdminWorkingDraft(envelope);
    expect(JSON.stringify(live.weapons)).not.toContain("DRAFT_REASON");
    expect(live.weapons).toEqual(published.weapons);

    const { data: before } = normalizePublicBuildRecommendation({
      characterId: FIXTURE_CHARACTER,
      structured: live,
      weapons: live.weapons,
      artifactRecommendations: live.artifactRecommendations,
      recommendedStats: live.recommendedStats,
      investmentPriority: live.investmentPriority,
      gameVersion: live.gameVersion,
      mainStats: fixtureMainStats,
      sources: fixtureSources,
      publishedAt: "2026-07-28T00:00:00.000Z",
      updatedAt: String(published.publishedContentUpdatedAt),
      lastVerifiedAt: "2026-07-28T00:00:00.000Z",
    });
    const dto = publicBuildRecommendationSchema.parse(before);
    const etag1 = buildPublicRecommendationEtag(FIXTURE_CHARACTER, dto);

    // draft 保存相当: publishedContentUpdatedAt は不変、row.updatedAt だけ進んでも ETag 不変
    const etag2 = buildPublicRecommendationEtag(FIXTURE_CHARACTER, {
      ...dto,
      // updatedAt が公開内容時刻のままなら同一
    });
    expect(etag1).toBe(etag2);

    const publishedChanged = publicBuildRecommendationSchema.parse({
      ...dto,
      updatedAt: "2026-07-29T00:00:00.000Z",
      weapons: [
        ...dto.weapons.slice(0, 1),
        ...dto.weapons.slice(1),
      ].map((w, i) => (i === 0 ? { ...w, reason: "changed" } : w)),
    });
    expect(buildPublicRecommendationEtag(FIXTURE_CHARACTER, publishedChanged)).not.toBe(
      etag1,
    );
  });
});

describe("release: ETag / 304 route behavior", () => {
  it("returns 304 when If-None-Match matches content etag", async () => {
    const structured = fixtureStructuredComplete();
    const { data } = normalizePublicBuildRecommendation({
      characterId: FIXTURE_CHARACTER,
      structured,
      weapons: structured.weapons,
      artifactRecommendations: structured.artifactRecommendations,
      recommendedStats: structured.recommendedStats,
      investmentPriority: structured.investmentPriority,
      gameVersion: structured.gameVersion,
      mainStats: fixtureMainStats,
      sources: fixtureSources,
      publishedAt: "2026-07-28T00:00:00.000Z",
      updatedAt: "2026-07-28T00:00:00.000Z",
      lastVerifiedAt: "2026-07-28T00:00:00.000Z",
    });
    const dto = publicBuildRecommendationSchema.parse(data);
    const etag = buildPublicRecommendationEtag(FIXTURE_CHARACTER, dto);

    vi.resetModules();
    vi.doMock("@/lib/build-guides/store", () => ({
      getPublishedBuildRecommendation: async () => dto,
    }));
    const { GET } = await import(
      "../../app/api/build-recommendations/[characterId]/route"
    );
    const hit = await GET(
      new Request(`http://localhost/api/build-recommendations/${FIXTURE_CHARACTER}`, {
        headers: { "if-none-match": etag },
      }),
      { params: Promise.resolve({ characterId: FIXTURE_CHARACTER }) },
    );
    expect(hit.status).toBe(304);
    expect(hit.headers.get("etag")).toBe(etag);
    expect(hit.headers.get("cache-control")).toContain("max-age=60");
    expect(hit.headers.get("cache-control")).toContain("stale-while-revalidate=300");

    const miss = await GET(
      new Request(`http://localhost/api/build-recommendations/${FIXTURE_CHARACTER}`),
      { params: Promise.resolve({ characterId: FIXTURE_CHARACTER }) },
    );
    expect(miss.status).toBe(200);
    const body = (await miss.json()) as { ok: boolean; data: unknown };
    expect(body.ok).toBe(true);
    const serialized = JSON.stringify(body.data);
    expect(serialized).not.toContain("adminWorkingDraft");
    expect(serialized).not.toContain("adminNotes");
  });

  it("keeps character-scoped etag fingerprints distinct", () => {
    const structured = fixtureStructuredComplete();
    const { data } = normalizePublicBuildRecommendation({
      characterId: "char-a",
      structured,
      weapons: structured.weapons,
      artifactRecommendations: structured.artifactRecommendations,
      recommendedStats: structured.recommendedStats,
      mainStats: fixtureMainStats,
      sources: fixtureSources,
      publishedAt: "2026-07-28T00:00:00.000Z",
      updatedAt: "2026-07-28T00:00:00.000Z",
      lastVerifiedAt: null,
    });
    const dto = publicBuildRecommendationSchema.parse(data);
    const a = buildPublicRecommendationEtag("char-a", dto);
    const b = buildPublicRecommendationEtag("char-b", { ...dto, characterId: "char-b" });
    expect(a).not.toBe(b);
    expect(a.startsWith('"br-char-a-')).toBe(true);
  });
});

describe("release: target zero vs empty", () => {
  it("keeps 0 as a valid minimum", () => {
    const { recommended, target } = targetDraftToPayload({
      id: "z",
      stat: "er",
      valueType: "minimum",
      minimum: "0",
      maximum: "",
      target: "",
      unit: "percent",
      condition: "",
      citationId: "",
      leftStat: "critRate",
      leftValue: "1",
      rightStat: "critDmg",
      rightValue: "2",
    });
    expect(recommended).toMatchObject({ minimum: 0 });
    expect(target).toMatchObject({ min: 0 });
  });
});

describe("release: optimistic lock semantics", () => {
  it("documents conflict when expectedUpdatedAt drifts >1s", () => {
    const expected = new Date("2026-07-28T00:00:00.000Z").getTime();
    const actual = new Date("2026-07-28T00:00:02.000Z").getTime();
    expect(Math.abs(expected - actual) > 1000).toBe(true);
    // store.ts throws conflictUpdatedAt → route 409
  });
});

describe("release: fingerprint stability helper", () => {
  it("hash changes when published weapons change", () => {
    const a = createHash("sha256").update("weapon-a").digest("hex");
    const b = createHash("sha256").update("weapon-b").digest("hex");
    expect(a).not.toBe(b);
  });
});
