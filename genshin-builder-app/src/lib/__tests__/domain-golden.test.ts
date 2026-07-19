/**
 * shared/domain-golden/cases.json を読み、Web ドメイン実装とパリティ検証する。
 */

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  calcPieceScore,
  inferScoreType,
  type ScoreType,
} from "@/lib/artifact-score";
import { makeBookmarkId } from "@/lib/bookmark-storage";
import {
  makeItemSourceKey,
  makeRangeSourceKey,
} from "@/lib/bookmark-utils";
import {
  clampInt,
  getNextStageRequirements,
  snapToLevelMark,
  type PromoteStage,
} from "@/lib/level-progression";
import {
  getRangeLevelRequirements,
  getRangeTalentRequirements,
} from "@/lib/material-requirements";
import { mainStatValue } from "@/lib/stats";
import type { TalentLevelUpgrade } from "@/lib/talent-progression";
import { snapTalentLevel } from "@/lib/talent-progression";
import { getWeaponExpBetweenMarks } from "@/lib/weapon-exp";
import type { CultivationKind } from "@/types/bookmark";

const GOLDEN_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../../shared/domain-golden/cases.json",
);

interface GoldenFile {
  version: number;
  suites: Record<string, { cases: GoldenCase[] }>;
}

interface GoldenCase {
  id: string;
  fn?: string;
  input: Record<string, unknown>;
  expected: unknown;
}

const character = {
  characterId: "hu-tao",
  characterName: "胡桃",
  characterIconUrl: "https://example.com/hu-tao.png",
};

function loadGolden(): GoldenFile {
  return JSON.parse(readFileSync(GOLDEN_PATH, "utf8")) as GoldenFile;
}

function linesByMaterialId(
  lines: { materialId: string; count: number; isMora?: boolean }[],
): Record<string, { count: number; isMora: boolean }> {
  const map: Record<string, { count: number; isMora: boolean }> = {};
  for (const line of lines) {
    map[line.materialId] = {
      count: line.count,
      isMora: line.isMora === true,
    };
  }
  return map;
}

describe("domain golden parity (shared/domain-golden)", () => {
  const golden = loadGolden();

  it("loads golden file", () => {
    expect(golden.version).toBe(1);
    expect(Object.keys(golden.suites).length).toBeGreaterThan(0);
  });

  describe("clampInt", () => {
    for (const c of golden.suites.clampInt.cases) {
      it(c.id, () => {
        const { value, min, max } = c.input as {
          value: unknown;
          min: number;
          max: number;
        };
        expect(clampInt(value, min, max)).toBe(c.expected);
      });
    }
  });

  describe("snapToLevelMark", () => {
    for (const c of golden.suites.snapToLevelMark.cases) {
      it(c.id, () => {
        const { value } = c.input as { value: unknown };
        expect(snapToLevelMark(value)).toBe(c.expected);
      });
    }
  });

  describe("getWeaponExpBetweenMarks", () => {
    for (const c of golden.suites.getWeaponExpBetweenMarks.cases) {
      it(c.id, () => {
        const { from, to, rarity } = c.input as {
          from: number;
          to: number;
          rarity: number;
        };
        expect(getWeaponExpBetweenMarks(from, to, rarity)).toBe(c.expected);
      });
    }
  });

  describe("bookmarkKeys", () => {
    for (const c of golden.suites.bookmarkKeys.cases) {
      it(c.id, () => {
        const input = c.input;
        if (c.fn === "makeBookmarkId") {
          expect(
            makeBookmarkId(
              String(input.sourceKey),
              String(input.materialId),
            ),
          ).toBe(c.expected);
          return;
        }

        const ctx = {
          kind: input.kind as CultivationKind,
          targetId: String(input.targetId),
          targetName: String(input.targetName),
          subLabel: input.subLabel as string | undefined,
          character,
        };

        if (c.fn === "makeRangeSourceKey") {
          expect(
            makeRangeSourceKey(ctx, Number(input.from), Number(input.to)),
          ).toBe(c.expected);
          return;
        }

        if (c.fn === "makeItemSourceKey") {
          expect(
            makeItemSourceKey(
              ctx,
              input.scope as "next" | "stage",
              String(input.materialId),
            ),
          ).toBe(c.expected);
          return;
        }

        throw new Error(`Unknown bookmarkKeys fn: ${c.fn}`);
      });
    }
  });

  describe("getNextStageRequirements", () => {
    for (const c of golden.suites.getNextStageRequirements.cases) {
      it(c.id, () => {
        const input = c.input as {
          currentLevel: number;
          kind: "character" | "weapon";
          weaponRarity: number;
          promotes: PromoteStage[];
        };
        const stage = getNextStageRequirements(
          input.currentLevel,
          input.promotes,
          input.kind,
          input.weaponRarity,
        );
        expect(stage).not.toBeNull();
        const expected = c.expected as {
          fromLevel: number;
          toLevel: number;
          expTotal: number;
          mora: number;
          materialsById: Record<string, number>;
          levelUpMaterialIds: string[];
        };
        expect(stage!.fromLevel).toBe(expected.fromLevel);
        expect(stage!.toLevel).toBe(expected.toLevel);
        expect(stage!.expTotal).toBe(expected.expTotal);
        expect(stage!.mora).toBe(expected.mora);
        const materialsById: Record<string, number> = {};
        for (const m of stage!.materials) {
          materialsById[m.materialId] = m.count;
        }
        expect(materialsById).toEqual(expected.materialsById);
        expect(stage!.levelUpMaterials.map((m) => m.materialId)).toEqual(
          expected.levelUpMaterialIds,
        );
      });
    }
  });

  describe("getRangeLevelRequirements", () => {
    for (const c of golden.suites.getRangeLevelRequirements.cases) {
      it(c.id, () => {
        const input = c.input as {
          fromLevel: number;
          toLevel: number;
          kind: "character" | "weapon";
          promotes: PromoteStage[];
        };
        const lines = getRangeLevelRequirements(
          input.fromLevel,
          input.toLevel,
          input.promotes,
          input.kind,
        );
        const expected = c.expected as {
          linesByMaterialId: Record<
            string,
            { count: number; isMora?: boolean }
          >;
        };
        expect(linesByMaterialId(lines)).toEqual(expected.linesByMaterialId);
      });
    }
  });

  describe("getRangeTalentRequirements", () => {
    for (const c of golden.suites.getRangeTalentRequirements.cases) {
      it(c.id, () => {
        const input = c.input as {
          fromLevel: number;
          toLevel: number;
          maxLevel: number;
          upgrades: TalentLevelUpgrade[];
        };
        const lines = getRangeTalentRequirements(
          input.fromLevel,
          input.toLevel,
          input.maxLevel,
          input.upgrades,
        );
        const expected = c.expected as {
          linesByMaterialId: Record<string, { count: number }>;
        };
        const actual: Record<string, { count: number }> = {};
        for (const line of lines) {
          actual[line.materialId] = { count: line.count };
        }
        expect(actual).toEqual(expected.linesByMaterialId);
      });
    }
  });

  describe("snapTalentLevel", () => {
    for (const c of golden.suites.snapTalentLevel.cases) {
      it(c.id, () => {
        const { value, max } = c.input as { value: unknown; max: number };
        expect(snapTalentLevel(value, max)).toBe(c.expected);
      });
    }
  });

  describe("artifactMainStatValue", () => {
    for (const c of golden.suites.artifactMainStatValue.cases) {
      it(c.id, () => {
        const { statName, level } = c.input as {
          statName: string;
          level: number;
        };
        expect(mainStatValue(statName, level)).toBe(c.expected);
      });
    }
  });

  describe("inferScoreType", () => {
    for (const c of golden.suites.inferScoreType.cases) {
      it(c.id, () => {
        const { specialProp, name } = c.input as {
          specialProp: string | null;
          name: string;
        };
        expect(inferScoreType(specialProp, name)).toBe(c.expected);
      });
    }
  });

  describe("calcPieceScore", () => {
    for (const c of golden.suites.calcPieceScore.cases) {
      it(c.id, () => {
        const input = c.input as {
          type: ScoreType;
          substats: { stat: string; value: number }[];
        };
        const piece = {
          setId: "",
          level: 0,
          mainStat: "",
          substats: input.substats,
        };
        expect(calcPieceScore(piece, input.type)).toBe(c.expected);
      });
    }
  });
});
