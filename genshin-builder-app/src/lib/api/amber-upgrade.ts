/**
 * Project Amber から突破・天賦・レベルEXPデータを取得する
 */

import { LEVEL_MARKS } from "@/lib/level-config";
import type {
  CharacterUpgradeData,
  LevelExpSegmentData,
  LevelUpMaterialData,
  PromoteStageData,
  TalentLevelUpgradeData,
  TalentUpgradeData,
  WeaponUpgradeData,
} from "./upgrade-types";
import {
  fetchJsonObject,
  UpstreamFetchError,
} from "./safe-json-fetch";

const BASE_URL = "https://gi.yatta.moe";
const REVALIDATE_SEC = 60 * 60 * 24;

const EXP_MATERIAL_IDS = {
  character: ["104001", "104002", "104003"],
  weapon: ["104011", "104012", "104013"],
} as const;

interface ApiTalentPromote {
  level?: number;
  costItems?: Record<string, number> | null;
  coinCost?: number | null;
}

interface ApiTalent {
  type: number;
  name: string;
  promote?: Record<string, ApiTalentPromote>;
}

interface ApiPromote {
  promoteLevel?: number;
  unlockMaxLevel?: number;
  costItems?: Record<string, number>;
  coinCost?: number;
  requiredPlayerLevel?: number;
}

interface ApiAvatarDetail {
  talent: Record<string, ApiTalent>;
  upgrade: { promote?: ApiPromote[] };
}

interface ApiWeaponDetail {
  upgrade: { promote?: ApiPromote[] };
  items?: Record<string, unknown>;
}

interface ApiMaterialDetail {
  name: string;
  description: string;
  type: string;
}

async function fetchJson<T>(path: string): Promise<T> {
  const json = await fetchJsonObject(`${BASE_URL}${path}`, {
    timeoutMs: 20_000,
    maxBytes: 2 * 1024 * 1024,
    retries: 2,
    revalidateSeconds: REVALIDATE_SEC,
  });
  if (
    json.response !== 200 ||
    typeof json.data !== "object" ||
    json.data === null ||
    Array.isArray(json.data)
  ) {
    throw new UpstreamFetchError("invalidData");
  }
  return json.data as T;
}

function parsePromotes(promotes: ApiPromote[] | undefined): PromoteStageData[] {
  return (promotes ?? []).map((promote) => {
    const promoteLevel = promote.promoteLevel ?? 0;
    const unlockMaxLevel = promote.unlockMaxLevel ?? 90;
    const coinCost = promote.coinCost ?? 0;
    const costs = promote.costItems ?? {};
    if (
      promoteLevel < 0 ||
      unlockMaxLevel < 1 ||
      coinCost < 0 ||
      Object.entries(costs).some(
        ([id, count]) =>
          id.trim() === "" ||
          !Number.isInteger(count) ||
          count < 0,
      )
    ) {
      throw new UpstreamFetchError("invalidData");
    }
    return {
      promoteLevel,
      unlockMaxLevel,
      costItems: costs,
      coinCost,
      requiredPlayerLevel: promote.requiredPlayerLevel,
    };
  });
}

function parseTalentUpgrades(
  promote: Record<string, ApiTalentPromote> | undefined,
): TalentLevelUpgradeData[] {
  if (!promote) return [];
  return Object.values(promote)
    .filter((p) => p.level != null)
    .sort((a, b) => (a.level ?? 0) - (b.level ?? 0))
    .map((promote) => {
      const level = promote.level!;
      const coinCost = promote.coinCost ?? 0;
      const costs = promote.costItems ?? {};
      if (
        level < 1 ||
        coinCost < 0 ||
        Object.entries(costs).some(
          ([id, count]) =>
            id.trim() === "" ||
            !Number.isInteger(count) ||
            count < 0,
        )
      ) {
        throw new UpstreamFetchError("invalidData");
      }
      return { level, costItems: costs, coinCost };
    });
}

/** キャラクターの突破・天賦強化データを取得 */
export async function fetchCharacterUpgradeFromApi(
  characterId: string,
): Promise<CharacterUpgradeData> {
  const data = await fetchJson<ApiAvatarDetail>(`/api/v2/jp/avatar/${characterId}`);
  if (
    !data.talent ||
    typeof data.talent !== "object" ||
    !data.upgrade ||
    typeof data.upgrade !== "object" ||
    !Array.isArray(data.upgrade.promote)
  ) {
    throw new UpstreamFetchError("invalidData");
  }

  const entries = Object.keys(data.talent)
    .sort((a, b) => Number(a) - Number(b))
    .map((key) => data.talent[key]);

  const active = entries.filter((t) => t.type === 0 || t.type === 1);
  const activeKinds: Array<"normal" | "skill" | "burst"> = [
    "normal",
    "skill",
    "burst",
  ];

  const talents: TalentUpgradeData[] = active
    .slice(0, 3)
    .map((t, i) => ({
      kind: activeKinds[i],
      upgrades: parseTalentUpgrades(t.promote),
    }))
    .filter((t) => t.upgrades.length > 0);

  const promotes = parsePromotes(data.upgrade.promote);
  if (promotes.length === 0) {
    throw new UpstreamFetchError("invalidData");
  }
  return {
    characterId,
    promotes,
    talents,
  };
}

/** 武器の突破・レベルアップ素材IDを取得 */
export async function fetchWeaponUpgradeFromApi(
  weaponId: string,
): Promise<WeaponUpgradeData> {
  const data = await fetchJson<ApiWeaponDetail>(`/api/v2/jp/weapon/${weaponId}`);
  if (
    !data.upgrade ||
    typeof data.upgrade !== "object" ||
    !Array.isArray(data.upgrade.promote)
  ) {
    throw new UpstreamFetchError("invalidData");
  }

  const levelUpItemIds = EXP_MATERIAL_IDS.weapon.filter(
    (id) => data.items?.[id] != null,
  );

  const promotes = parsePromotes(data.upgrade.promote);
  if (promotes.length === 0) {
    throw new UpstreamFetchError("invalidData");
  }
  return {
    weaponId,
    promotes,
    levelUpItemIds:
      levelUpItemIds.length > 0 ? [...levelUpItemIds] : [...EXP_MATERIAL_IDS.weapon],
  };
}

/** 素材詳細から経験値をパース（description 内の「経験値XXXX」） */
export function parseExpFromDescription(description: string): number | null {
  const match = description.match(/経験値(\d+)/);
  return match ? Number(match[1]) : null;
}

/** 経験値素材の詳細をAPIから取得 */
export async function fetchLevelUpMaterialsFromApi(
  onFetch?: () => void,
): Promise<LevelUpMaterialData[]> {
  const result: LevelUpMaterialData[] = [];

  for (const targetType of ["character", "weapon"] as const) {
    for (const id of EXP_MATERIAL_IDS[targetType]) {
      onFetch?.();
      const detail = await fetchJson<ApiMaterialDetail>(
        `/api/v2/jp/material/${id}`,
      );
      if (
        typeof detail.name !== "string" ||
        detail.name.trim() === "" ||
        typeof detail.description !== "string" ||
        typeof detail.type !== "string"
      ) {
        throw new UpstreamFetchError("invalidData");
      }
      const exp = parseExpFromDescription(detail.description);
      if (exp == null || exp <= 0) {
        throw new UpstreamFetchError("invalidData");
      }
      result.push({
        materialId: id,
        name: detail.name,
        exp,
        targetType,
      });
    }
  }

  if (result.length !== 6) {
    throw new UpstreamFetchError("invalidData");
  }
  return result;
}

/**
 * 目盛り間必要EXP（Amber API に直接のエンドポイントがないため、
 * ゲーム内実測値を同期時にDBへ保存する。値は community verified data）
 */
export function buildLevelExpSegments(): LevelExpSegmentData[] {
  const characterExp: Record<string, number> = {
    "1-20": 12_275,
    "20-30": 57_900,
    "30-40": 65_700,
    "40-50": 39_300,
    "50-60": 94_800,
    "60-70": 114_300,
    "70-80": 280_800,
    "80-90": 393_750,
  };

  const weaponExpByRarity: Record<number, Record<string, number>> = {
    3: {
      "1-20": 53_475,
      "20-30": 127_978,
      "30-40": 145_247,
      "40-50": 275_350,
      "50-60": 408_650,
      "60-70": 572_725,
      "70-80": 772_825,
      "80-90": 1_638_650,
    },
    4: {
      "1-20": 81_000,
      "20-30": 194_512,
      "30-40": 220_613,
      "40-50": 418_725,
      "50-60": 618_400,
      "60-70": 866_675,
      "70-80": 1_168_350,
      "80-90": 2_476_475,
    },
    5: {
      "1-20": 121_550,
      "20-30": 291_591,
      "30-40": 331_209,
      "40-50": 628_150,
      "50-60": 927_675,
      "60-70": 1_299_125,
      "70-80": 1_750_375,
      "80-90": 3_714_775,
    },
  };

  const segments: LevelExpSegmentData[] = [];

  for (let i = 0; i < LEVEL_MARKS.length - 1; i++) {
    const from = LEVEL_MARKS[i];
    const to = LEVEL_MARKS[i + 1];
    const key = `${from}-${to}`;
    const charExp = characterExp[key] ?? 0;
    segments.push({
      id: `character-0-${from}-${to}`,
      targetType: "character",
      rarity: 0,
      fromLevel: from,
      toLevel: to,
      expRequired: charExp,
      moraRequired: Math.round(charExp / 10),
    });

    for (const rarity of [3, 4, 5]) {
      const exp = weaponExpByRarity[rarity][key] ?? 0;
      segments.push({
        id: `weapon-${rarity}-${from}-${to}`,
        targetType: "weapon",
        rarity,
        fromLevel: from,
        toLevel: to,
        expRequired: exp,
        moraRequired: Math.round(exp / 10),
      });
    }
  }

  return segments;
}

/** 並列数を制限して配列を処理（欠損結果は invalidData として拒否） */
export async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  if (items.length === 0) return [];

  const results: R[] = new Array(items.length);
  let index = 0;

  async function worker() {
    while (true) {
      const i = index++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, worker),
  );
  if (results.some((value) => value === undefined)) {
    throw new UpstreamFetchError("invalidData");
  }
  return results;
}
