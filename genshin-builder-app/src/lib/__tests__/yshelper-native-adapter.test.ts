import { describe, expect, it } from "vitest";

import {
  CanonicalV1YshelperAdapter,
  configuredYshelperAdapter,
  NativeV1YshelperAdapter,
  YshelperAdapterNotConfiguredError,
} from "@/lib/yshelper/adapter";
import {
  YSHELPER_CHARACTER_ID_BY_NAME,
} from "@/lib/yshelper/character-id-map";
import { hashBattleStats } from "@/lib/yshelper/hash";
import { createTeamKey } from "@/lib/yshelper/normalize";
import { YshelperSchemaError } from "@/lib/yshelper/schema";
import {
  yshelperNativeAbyssFixture,
  yshelperNativeStygianAllFixture,
  yshelperNativeStygianNandu6Fixture,
} from "./fixtures/yshelper-native";

const adapter = new NativeV1YshelperAdapter();

function payload(value: unknown): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

describe("YShelper native-v1 adapter", () => {
  it("maps the known Ambor alias to Amber and leaves Traveler unresolved", () => {
    expect(YSHELPER_CHARACTER_ID_BY_NAME.amber).toBe("10000021");
    expect(YSHELPER_CHARACTER_ID_BY_NAME.ambor).toBe("10000021");
    expect(YSHELPER_CHARACTER_ID_BY_NAME.traveler).toBeUndefined();
  });

  it("selects native-v1 from configuredYshelperAdapter", () => {
    expect(configuredYshelperAdapter({ YSHELPER_ADAPTER_MODE: "native-v1" }))
      .toBeInstanceOf(NativeV1YshelperAdapter);
    expect(
      configuredYshelperAdapter({ YSHELPER_ADAPTER_MODE: "canonical-v1" }),
    ).toBeInstanceOf(CanonicalV1YshelperAdapter);
    expect(() => configuredYshelperAdapter({})).toThrow(
      YshelperAdapterNotConfiguredError,
    );
  });

  it("normalizes Spiral Abyss character statistics", () => {
    const value = adapter.adapt(
      "abyss",
      payload(yshelperNativeAbyssFixture),
    );

    expect(value.sampleSize).toBe(56_925);
    expect(value.sourceVersion).toBe("6.7-phase-i");
    expect(value.seasonId).toBe("abyss-6.7-phase-i-2026-07-18");
    expect(value.sourceUpdatedAt).toBe("2026-07-18T14:00:00.000Z");

    const ineffa = value.characters.find(
      (character) => character.characterId === "10000116",
    );
    expect(ineffa).toMatchObject({
      usageCount: 30_057,
      ownershipRate: 0.567,
      usageAmongOwnersRate: 0.932,
    });
    expect(ineffa?.usageRate).toBeCloseTo(30_057 / 56_925, 8);

    const amber = value.characters.find(
      (character) => character.characterId === "10000021",
    );
    expect(amber).toMatchObject({
      usageCount: 21,
      ownershipRate: 1,
      usageAmongOwnersRate: 0.001,
    });
  });

  it("keeps only complete four-character Spiral Abyss teams with sides", () => {
    const value = adapter.adapt(
      "abyss",
      payload(yshelperNativeAbyssFixture),
    );
    const expectedTeamKey = createTeamKey([
      "10000120",
      "10000125",
      "10000116",
      "10000043",
    ]);

    expect(value.teams.length).toBe(2);
    expect(
      value.teams.every(
        (team) =>
          team.members.length === 4 &&
          new Set(team.members).size === 4 &&
          team.teamKey === expectedTeamKey,
      ),
    ).toBe(true);
    expect(new Set(value.teams.map((team) => team.side))).toEqual(
      new Set(["upper", "lower"]),
    );

    const totalUsageRate = value.teams.reduce(
      (sum, team) => sum + team.usageRate,
      0,
    );
    expect(totalUsageRate).toBeCloseTo(10_032 / 56_925, 8);
  });

  it("accepts string counts from Stygian Onslaught difficulty 6", () => {
    const value = adapter.adapt(
      "stygian",
      payload(yshelperNativeStygianNandu6Fixture),
    );

    expect(value.sampleSize).toBe(1_381);

    const columbina = value.characters.find(
      (character) => character.characterId === "10000125",
    );
    expect(columbina).toMatchObject({
      usageCount: 1_240,
      ownershipRate: 0.948,
      usageAmongOwnersRate: 0.947,
    });
    expect(columbina?.usageRate).toBeCloseTo(1_240 / 1_381, 8);

    const expectedTeamKey = createTeamKey([
      "10000125",
      "10000126",
      "10000130",
      "10000127",
    ]);
    const teamUsageRate = value.teams
      .filter((team) => team.teamKey === expectedTeamKey)
      .reduce((sum, team) => sum + team.usageRate, 0);

    expect(teamUsageRate).toBeCloseTo(259 / 1_381, 8);
    expect(value.teams.some((team) => team.side === "middle")).toBe(true);
  });

  it("excludes a team whose Traveler element cannot be resolved", () => {
    const value = adapter.adapt(
      "stygian",
      payload(yshelperNativeStygianAllFixture),
    );

    expect(
      value.characters.some(
        (character) => character.characterId.startsWith("10000005-"),
      ),
    ).toBe(false);
    expect(
      value.teams.every(
        (team) =>
          team.members.length === 4 &&
          team.members.every(
            (characterId) => !characterId.startsWith("10000005-"),
          ),
      ),
    ).toBe(true);
    expect(value.teams).toHaveLength(1);
  });

  it("rejects a non-success response", () => {
    expect(() =>
      adapter.adapt(
        "abyss",
        payload({
          ...yshelperNativeAbyssFixture,
          code: 500,
        }),
      ),
    ).toThrow(YshelperSchemaError);
  });

  it("rejects invalid rates, negatives, and bad dates", () => {
    expect(() =>
      adapter.adapt(
        "abyss",
        payload({
          ...yshelperNativeAbyssFixture,
          last_update: "not-a-date",
        }),
      ),
    ).toThrow(YshelperSchemaError);

    expect(() =>
      adapter.adapt(
        "abyss",
        payload({
          ...yshelperNativeAbyssFixture,
          last_update: "2026-02-30",
        }),
      ),
    ).toThrow(YshelperSchemaError);

    const overRate = payload(yshelperNativeAbyssFixture);
    const firstList = (
      (overRate.result as unknown[])[0] as unknown[]
    )[0] as Record<string, unknown>;
    const characters = firstList.list as Record<string, unknown>[];
    characters[0] = { ...characters[0], own_rate: 120 };
    expect(() => adapter.adapt("abyss", overRate)).toThrow(YshelperSchemaError);

    const negative = payload(yshelperNativeAbyssFixture);
    const negList = (
      (negative.result as unknown[])[0] as unknown[]
    )[0] as Record<string, unknown>;
    const negCharacters = negList.list as Record<string, unknown>[];
    negCharacters[0] = { ...negCharacters[0], use: -1 };
    expect(() => adapter.adapt("abyss", negative)).toThrow(YshelperSchemaError);
  });

  it("rejects top_own=0, use above sample, and scientific-notation counts", () => {
    expect(() =>
      adapter.adapt(
        "abyss",
        payload({
          ...yshelperNativeAbyssFixture,
          top_own: 0,
        }),
      ),
    ).toThrow(YshelperSchemaError);

    const overUse = payload(yshelperNativeAbyssFixture);
    const overList = (
      (overUse.result as unknown[])[0] as unknown[]
    )[0] as Record<string, unknown>;
    const overCharacters = overList.list as Record<string, unknown>[];
    overCharacters[0] = { ...overCharacters[0], use: 56_926 };
    expect(() => adapter.adapt("abyss", overUse)).toThrow(YshelperSchemaError);

    const scientific = payload(yshelperNativeAbyssFixture);
    const sciList = (
      (scientific.result as unknown[])[0] as unknown[]
    )[0] as Record<string, unknown>;
    const sciCharacters = sciList.list as Record<string, unknown>[];
    sciCharacters[0] = { ...sciCharacters[0], use: "1e3" };
    expect(() => adapter.adapt("abyss", scientific)).toThrow(
      YshelperSchemaError,
    );
  });

  it("fails closed on non-Traveler unresolved character names", () => {
    const broken = payload(yshelperNativeAbyssFixture);
    const firstList = (
      (broken.result as unknown[])[0] as unknown[]
    )[0] as Record<string, unknown>;
    const characters = firstList.list as Record<string, unknown>[];
    characters[0] = {
      ...characters[0],
      ename: "CompletelyUnknownHero",
      name: "CompletelyUnknownHero",
    };
    expect(() => adapter.adapt("abyss", broken)).toThrow(YshelperSchemaError);
  });

  it("rejects mismatched side usage totals", () => {
    const broken = payload(yshelperNativeStygianNandu6Fixture);
    const teams = (broken.result as unknown[])[3] as Record<string, unknown>[];
    teams[0] = { ...teams[0], mid_use_num: 1, use: 259 };
    expect(() => adapter.adapt("stygian", broken)).toThrow(YshelperSchemaError);
  });

  it("excludes duplicate-character four-member teams", () => {
    const broken = payload(yshelperNativeStygianNandu6Fixture);
    const teams = (broken.result as unknown[])[3] as Record<string, unknown>[];
    const roles = [...(teams[0].role as Record<string, unknown>[])];
    roles[3] = { ...roles[0] };
    teams[0] = { ...teams[0], role: roles };
    const value = adapter.adapt("stygian", broken);
    expect(value.teams).toHaveLength(0);
  });

  it("produces a stable hash for identical inputs", () => {
    const left = adapter.adapt("abyss", payload(yshelperNativeAbyssFixture));
    const right = adapter.adapt("abyss", payload(yshelperNativeAbyssFixture));
    expect(hashBattleStats(left)).toBe(hashBattleStats(right));
    expect(hashBattleStats(left)).toMatch(/^sha256:[a-f0-9]{64}$/);
  });
});
