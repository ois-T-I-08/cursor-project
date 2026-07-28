import { describe, expect, it } from "vitest";
import {
  buildArtifactSetsPayload,
  formatArtifactCompositionPreview,
  inferCompositionMode,
  stripAdminWorkingDraft,
  targetDraftToPayload,
  unitWarnForStat,
} from "../build-guides/guide-admin-form";

describe("artifact composition helpers", () => {
  it("builds 4 / 2 / 2+2 / undetermined sets without inventing pieces", () => {
    expect(buildArtifactSetsPayload("four", "15020", "")).toEqual([
      { setId: "15020", pieces: 4 },
    ]);
    expect(buildArtifactSetsPayload("two", "15020", "")).toEqual([
      { setId: "15020", pieces: 2 },
    ]);
    expect(buildArtifactSetsPayload("two_two", "15020", "15017")).toEqual([
      { setId: "15020", pieces: 2 },
      { setId: "15017", pieces: 2 },
    ]);
    expect(buildArtifactSetsPayload("undetermined", "15020", "")).toEqual([
      { setId: "15020", pieces: null },
    ]);
  });

  it("infers undetermined when pieces null", () => {
    expect(
      inferCompositionMode([{ setId: "15020", pieces: null }]),
    ).toBe("undetermined");
  });

  it("formats preview from structured sets", () => {
    expect(
      formatArtifactCompositionPreview("four", "15020", "", (id) =>
        id === "15020" ? "絶縁の旗印" : id,
      ),
    ).toBe("絶縁の旗印 ×4");
    expect(
      formatArtifactCompositionPreview("two_two", "a", "b", (id) =>
        id === "a" ? "剣闘士" : "しめ縄",
      ),
    ).toBe("剣闘士 ×2\nしめ縄 ×2");
  });
});

describe("targetDraftToPayload", () => {
  it("keeps only minimum fields for minimum valueType", () => {
    const { recommended, target } = targetDraftToPayload({
      id: "1",
      stat: "er",
      valueType: "minimum",
      minimum: "180",
      maximum: "999",
      target: "200",
      unit: "percent",
      condition: "",
      citationId: "",
      leftStat: "critRate",
      leftValue: "1",
      rightStat: "critDmg",
      rightValue: "2",
    });
    expect(recommended).toMatchObject({
      valueType: "minimum",
      minimum: 180,
      unit: "percent",
    });
    expect(recommended).not.toHaveProperty("maximum");
    expect(recommended).not.toHaveProperty("recommended");
    expect(target).toEqual({ stat: "er", unit: "percent", min: 180 });
  });

  it("stores ratio without targets fallback", () => {
    const { recommended, target } = targetDraftToPayload({
      id: "1",
      stat: "critRate",
      valueType: "ratio",
      minimum: "",
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
    expect(recommended).toMatchObject({
      valueType: "ratio",
      leftStat: "critRate",
      leftValue: 1,
      rightStat: "critDmg",
      rightValue: 2,
    });
    expect(target).toBeNull();
  });

  it("warns on bad unit combinations", () => {
    expect(unitWarnForStat("critRate", "flat")).toBeTruthy();
    expect(unitWarnForStat("em", "percent")).toBeTruthy();
    expect(unitWarnForStat("em", "flat")).toBeNull();
  });
});

describe("stripAdminWorkingDraft", () => {
  it("removes draft envelope for public payload", () => {
    const stripped = stripAdminWorkingDraft({
      weapons: [{ weaponId: "1" }],
      adminWorkingDraft: { structured: { weapons: [{ weaponId: "2" }] } },
    });
    expect(stripped.weapons).toEqual([{ weaponId: "1" }]);
    expect(stripped.adminWorkingDraft).toBeUndefined();
  });
});
