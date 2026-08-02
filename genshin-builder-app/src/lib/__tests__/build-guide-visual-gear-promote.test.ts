import { describe, expect, it } from "vitest";
import {
  buildMasterNameMaps,
  promoteResolvedGearMentionsForAutoPublish,
} from "../build-guides/visual-gear-promote";

const weapons = buildMasterNameMaps([
  { id: "the_stringless", name: "絶弦" },
  { id: "skyward_harp", name: "天空の翼" },
]);
const sets = buildMasterNameMaps([
  { id: "thundering_fury", name: "雷のような怒り" },
  { id: "gladiators_finale", name: "剣闘士のフィナーレ" },
]);

describe("promoteResolvedGearMentionsForAutoPublish", () => {
  it("promotes name-resolved weapons and clears pendingMentions", () => {
    const result = promoteResolvedGearMentionsForAutoPublish({
      structured: {
        pendingMentions: {
          weapons: [
            {
              displayName: "絶弦",
              weaponId: null,
              dataOrigin: "evidence_mention",
              adminConfirmed: false,
            },
          ],
          artifactSets: [],
        },
        structuredReviewStatus: "review_required",
      },
      evidenceWeapons: [
        {
          exactVisibleText: "天空の翼",
          normalizedWeaponId: null,
          videoId: "abc12345678",
        },
      ],
      weaponsById: weapons.byId,
      weaponsByName: weapons.byName,
      setsById: sets.byId,
      setsByName: sets.byName,
    });

    expect(result.promotedWeapons).toBe(2);
    expect(result.deferredWeapons).toBe(0);
    expect(result.structured.pendingMentions).toEqual({
      weapons: [],
      artifactSets: [],
    });
    const publishedWeapons = result.structured.weapons as Array<
      Record<string, unknown>
    >;
    expect(publishedWeapons).toHaveLength(2);
    // Evidence mentions are processed before pendingMentions.
    expect(publishedWeapons[0]).toMatchObject({
      weaponId: "skyward_harp",
      citationId: "source-abc12345678",
      adminConfirmed: true,
      dataOrigin: "structured",
    });
    expect(publishedWeapons[1]).toMatchObject({
      weaponId: "the_stringless",
      displayName: "絶弦",
      adminConfirmed: true,
    });
  });

  it("promotes a single resolved artifact set as 4pc", () => {
    const result = promoteResolvedGearMentionsForAutoPublish({
      structured: { pendingMentions: { weapons: [], artifactSets: [] } },
      evidenceArtifacts: [
        {
          exactVisibleText: "雷のような怒り",
          normalizedArtifactSetId: null,
          videoId: "vidWeapon01",
        },
      ],
      weaponsById: weapons.byId,
      weaponsByName: weapons.byName,
      setsById: sets.byId,
      setsByName: sets.byName,
    });

    expect(result.promotedArtifacts).toBe(1);
    expect(result.structured.artifactRecommendations).toEqual([
      expect.objectContaining({
        adminConfirmed: true,
        dataOrigin: "structured",
        sets: [{ setId: "thundering_fury", pieces: 4 }],
        citationId: "source-vidWeapon01",
      }),
    ]);
  });

  it("does not promote multiple artifact sets (no 4+2 guessing)", () => {
    const result = promoteResolvedGearMentionsForAutoPublish({
      structured: {},
      evidenceArtifacts: [
        { exactVisibleText: "雷のような怒り" },
        { exactVisibleText: "剣闘士のフィナーレ" },
      ],
      weaponsById: weapons.byId,
      weaponsByName: weapons.byName,
      setsById: sets.byId,
      setsByName: sets.byName,
    });

    expect(result.promotedArtifacts).toBe(0);
    expect(result.deferredArtifacts).toBe(2);
    expect(result.structured.artifactRecommendations).toEqual([]);
    expect(result.structured.pendingMentions).toEqual({
      weapons: [],
      artifactSets: [],
    });
  });

  it("defers unresolved mentions but still clears pending for auto-publish", () => {
    const result = promoteResolvedGearMentionsForAutoPublish({
      structured: {
        pendingMentions: {
          weapons: [{ displayName: "架空の武器XYZ" }],
          artifactSets: [],
        },
      },
      weaponsById: weapons.byId,
      weaponsByName: weapons.byName,
      setsById: sets.byId,
      setsByName: sets.byName,
    });

    expect(result.promotedWeapons).toBe(0);
    expect(result.deferredWeapons).toBe(1);
    expect(result.structured.weapons).toEqual([]);
    expect(result.structured.pendingMentions).toEqual({
      weapons: [],
      artifactSets: [],
    });
    expect(result.structured.deferredMentions).toEqual({
      weapons: 1,
      artifactSets: 0,
    });
  });

  it("resolves by known weapon id without guessing names", () => {
    const result = promoteResolvedGearMentionsForAutoPublish({
      structured: {},
      evidenceWeapons: [
        {
          exactVisibleText: "なにか違う表記",
          normalizedWeaponId: "the_stringless",
        },
      ],
      weaponsById: weapons.byId,
      weaponsByName: weapons.byName,
      setsById: sets.byId,
      setsByName: sets.byName,
    });

    expect(result.promotedWeapons).toBe(1);
    expect(
      (result.structured.weapons as Array<Record<string, unknown>>)[0],
    ).toMatchObject({
      weaponId: "the_stringless",
      displayName: "絶弦",
    });
  });
});
