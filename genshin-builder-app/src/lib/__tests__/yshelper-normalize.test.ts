import { describe, expect, it } from "vitest";

import { CanonicalV1YshelperAdapter } from "@/lib/yshelper/adapter";
import { hashBattleStats } from "@/lib/yshelper/hash";
import { createTeamKey } from "@/lib/yshelper/normalize";
import { YshelperSchemaError } from "@/lib/yshelper/schema";
import {
  publishableBattleStats,
  validateBattleStats,
} from "@/lib/yshelper/validate";
import { yshelperCanonicalFixture } from "./fixtures/yshelper-canonical-v1";

const adapter = new CanonicalV1YshelperAdapter();
const known = new Set(["10000001", "10000002", "10000003", "10000004"]);

describe("YShelper canonical-v1 adapter", () => {
  it("builds a stable order-independent team key", () => {
    expect(createTeamKey(["3", "1", "4", "2"])).toBe("1:2:3:4");
  });

  it("converts percent only when rateUnit explicitly says percent", () => {
    const value = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({
        rateUnit: "percent",
        teams: [
          {
            characters: ["10000004", "10000003", "10000002", "10000001"],
            usageRate: 25,
            metadata: {},
          },
        ],
        characters: [{ characterId: "10000001", usageRate: 50 }],
      }),
    );
    expect(value.teams[0].usageRate).toBe(0.25);
    expect(value.characters[0].usageRate).toBe(0.5);
  });

  it("does not infer a percent from the numeric magnitude", () => {
    expect(() =>
      adapter.adapt(
        "abyss",
        yshelperCanonicalFixture({
          rateUnit: "ratio",
          characters: [{ characterId: "10000001", usageRate: 50 }],
        }),
      ),
    ).toThrow(YshelperSchemaError);
  });

  it("merges duplicate team permutations deterministically", () => {
    const value = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({
        teams: [
          {
            characters: ["10000001", "10000002", "10000003", "10000004"],
            usageRate: 0.1,
            usageCount: 100,
            side: "upper",
            stageKey: "12-1",
            metadata: {},
          },
          {
            characters: ["10000004", "10000003", "10000002", "10000001"],
            usageRate: 0.15,
            usageCount: 150,
            side: "upper",
            stageKey: "12-1",
            metadata: {},
          },
        ],
      }),
    );
    expect(value.teams).toHaveLength(1);
    expect(value.teams[0]).toMatchObject({
      teamKey: "10000001:10000002:10000003:10000004",
      usageRate: 0.25,
      usageCount: 250,
    });
  });

  it.each([
    {
      field: "duplicate member",
      overrides: {
        teams: [
          {
            characters: ["10000001", "10000001", "10000003", "10000004"],
            usageRate: 0.1,
            metadata: {},
          },
        ],
      },
    },
    {
      field: "duplicate character scope",
      overrides: {
        characters: [
          { characterId: "10000001", usageRate: 0.1 },
          { characterId: "10000001", usageRate: 0.2 },
        ],
      },
    },
    {
      field: "unknown response field",
      overrides: { unexpected: "must be rejected" },
    },
  ])("rejects $field", ({ overrides }) => {
    expect(() =>
      adapter.adapt("abyss", yshelperCanonicalFixture(overrides)),
    ).toThrow(YshelperSchemaError);
  });

  it.each([-0.1, 1.1, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects an abnormal ratio %s",
    (usageRate) => {
      expect(() =>
        adapter.adapt(
          "abyss",
          yshelperCanonicalFixture({
            characters: [{ characterId: "10000001", usageRate }],
          }),
        ),
      ).toThrow(YshelperSchemaError);
    },
  );

  it("rejects a negative usage count", () => {
    expect(() =>
      adapter.adapt(
        "abyss",
        yshelperCanonicalFixture({
          characters: [
            {
              characterId: "10000001",
              usageRate: 0.5,
              usageCount: -1,
            },
          ],
        }),
      ),
    ).toThrow(YshelperSchemaError);
  });

  it("produces the same hash across object, team and member ordering", () => {
    const first = publishableBattleStats(
      validateBattleStats(
        adapter.adapt("abyss", yshelperCanonicalFixture()),
        known,
      ).value,
    );
    const second = {
      ...first,
      teams: first.teams.map((team) => ({
        ...team,
        members: [...team.members].reverse(),
      })),
      characters: [...first.characters].reverse(),
      metadata: { z: 1, a: 2 },
    };
    const firstWithMetadata = { ...first, metadata: { a: 2, z: 1 } };
    expect(hashBattleStats(second)).toBe(hashBattleStats(firstWithMetadata));
  });
});

describe("YShelper publication validation", () => {
  it("classifies an empty response as invalid", () => {
    const value = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({ teams: [], characters: [] }),
    );
    expect(validateBattleStats(value, known).state).toBe("invalid");
  });

  it("marks a large unknown-ID ratio suspicious and excludes it from publication", () => {
    const value = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({
        teams: [],
        characters: [{ characterId: "19999999", usageRate: 0.5 }],
      }),
    );
    const validation = validateBattleStats(value, known);
    expect(validation.state).toBe("suspicious");
    expect(publishableBattleStats(validation.value).characters).toEqual([]);
  });

  it("detects sudden record count and usage-rate changes", () => {
    const previous = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({
        teams: [],
        characters: Array.from({ length: 10 }, (_, index) => ({
          characterId: `100000${String(index).padStart(2, "0")}`,
          usageRate: index === 1 ? 0.9 : 0.1,
        })),
      }),
    );
    const current = adapter.adapt(
      "abyss",
      yshelperCanonicalFixture({
        teams: [],
        characters: [{ characterId: "10000001", usageRate: 0.1 }],
      }),
    );
    const allKnown = new Set([
      ...previous.characters.map((item) => item.characterId),
      "10000001",
    ]);
    const result = validateBattleStats(current, allKnown, previous);
    expect(result.state).toBe("suspicious");
    expect(result.issues.map((issue) => issue.code)).toContain(
      "record_count_drop",
    );
    expect(result.issues.map((issue) => issue.code)).toContain(
      "usage_rate_shift",
    );
  });
});
