import { describe, expect, it } from "vitest";
import {
  validateStructuredDraft,
  validateStructuredForPublish,
} from "../build-guides/structured-admin";

const knownWeaponIds = new Set(["13501", "15501"]);

describe("validateStructuredDraft", () => {
  it("allows incomplete artifact sets as warnings", () => {
    const issues = validateStructuredDraft({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "review_required",
        pendingMentions: {
          weapons: [{ weaponId: "13501" }],
          artifactSets: [],
        },
        weapons: [],
        artifactRecommendations: [
          {
            sets: [{ setId: "", pieces: null }],
            adminConfirmed: false,
          },
        ],
      },
      knownWeaponIds,
    });
    expect(issues.some((i) => i.level === "error")).toBe(false);
    expect(issues.some((i) => i.path.includes("pendingMentions"))).toBe(true);
    expect(issues.some((i) => i.message.includes("pieces"))).toBe(true);
  });

  it("rejects invalid investmentPriority as error", () => {
    const issues = validateStructuredDraft({
      characterId: "hu-tao",
      structured: { investmentPriority: "very_high" },
    });
    expect(issues.some((i) => i.level === "error" && i.path === "investmentPriority")).toBe(
      true,
    );
  });
});

describe("validateStructuredForPublish", () => {
  it("blocks pending mentions and unconfirmed candidates", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "review_required",
        pendingMentions: { weapons: [{ weaponId: "13501" }], artifactSets: [] },
        weapons: [
          {
            weaponId: "13501",
            adminConfirmed: false,
            dataOrigin: "manual",
          },
        ],
        artifactRecommendations: [],
      },
      sources: [{ id: "source-vid1", videoId: "vid1" }],
      knownWeaponIds,
    });
    expect(issues.some((i) => i.path === "pendingMentions" && i.level === "error")).toBe(
      true,
    );
    expect(issues.some((i) => i.path === "weapons[0]" && i.level === "error")).toBe(true);
    expect(
      issues.some((i) => i.path === "structuredReviewStatus" && i.level === "error"),
    ).toBe(true);
  });

  it("requires explicit item confirmation and a completed structured review", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "draft",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [{ weaponId: "13501" }],
        artifactRecommendations: [
          { sets: [{ setId: "15020", pieces: 4 }] },
        ],
      },
      sources: [],
      knownWeaponIds,
      knownSetIds: new Set(["15020"]),
      artifactMasterAvailable: true,
    });

    expect(
      issues.some((i) => i.path === "weapons[0]" && i.level === "error"),
    ).toBe(true);
    expect(
      issues.some(
        (i) =>
          i.path === "artifactRecommendations[0]" && i.level === "error",
      ),
    ).toBe(true);
    expect(
      issues.some(
        (i) =>
          i.path === "structuredReviewStatus" && i.level === "error",
      ),
    ).toBe(true);
  });

  it("blocks unresolved citationId, unknown weapon, and unknown setId", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "admin_confirmed",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [
          {
            weaponId: "99999",
            adminConfirmed: true,
            citationId: "source-missing",
          },
        ],
        artifactRecommendations: [
          {
            sets: [{ setId: "15020", pieces: 4 }],
            adminConfirmed: true,
          },
        ],
      },
      sources: [{ id: "source-vid1", videoId: "vid1" }],
      knownWeaponIds,
      knownSetIds: new Set(["15017"]),
    });
    expect(issues.some((i) => i.message.includes("不正な武器ID"))).toBe(true);
    expect(issues.some((i) => i.message.includes("解決不能な citationId"))).toBe(true);
    expect(issues.some((i) => i.message.includes("マスターに存在しない setId"))).toBe(
      true,
    );
  });

  it("blocks undetermined artifact composition on publish", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "admin_confirmed",
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
      sources: [],
      knownWeaponIds,
      knownSetIds: new Set(["15020"]),
    });
    expect(
      issues.some((i) => i.message.includes("未確定の聖遺物構成は公開できません")),
    ).toBe(true);
  });

  it("accepts confirmed 2+2 with resolvable citation", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "admin_confirmed",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [
          {
            weaponId: "13501",
            adminConfirmed: true,
            citationId: "source-vid1",
          },
        ],
        artifactRecommendations: [
          {
            sets: [
              { setId: "15017", pieces: 2 },
              { setId: "15008", pieces: 2 },
            ],
            adminConfirmed: true,
            citationId: "source-vid1",
          },
        ],
      },
      sources: [{ id: "source-vid1", videoId: "vid1" }],
      knownWeaponIds,
    });
    expect(issues.filter((i) => i.level === "error")).toEqual([]);
  });

  it("rejects invalid 4pc mixed sets", () => {
    const issues = validateStructuredForPublish({
      characterId: "hu-tao",
      structured: {
        structuredReviewStatus: "draft",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [],
        artifactRecommendations: [
          {
            sets: [
              { setId: "15017", pieces: 4 },
              { setId: "15008", pieces: 2 },
            ],
            adminConfirmed: true,
          },
        ],
      },
      sources: [],
      knownWeaponIds,
    });
    expect(
      issues.some(
        (i) =>
          i.level === "error" &&
          i.message.includes("公開可能なセット構成ではありません"),
      ),
    ).toBe(true);
  });
});
