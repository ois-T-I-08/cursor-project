/**
 * Project Amber（gi.yatta.moe）用のデータ取得プロバイダー。
 *
 * genshin.jmp.blue が2024年夏以降更新停止しているため、
 * 最新キャラまで収録されており日本語名も取得できるこちらを使用する。
 *
 * このファイルの責務は「外部APIのレスポンスを正規化済みの型に変換すること」のみ。
 */

import type {
  GameDataProvider,
  MasterCharacter,
  MasterMaterial,
  MasterWeapon,
} from "./types";
import { inferScoreType } from "@/lib/artifact-score";
import {
  fetchJsonObject,
  UpstreamFetchError,
} from "./safe-json-fetch";

const BASE_URL = "https://gi.yatta.moe";
const ASSET_URL = `${BASE_URL}/assets/UI`;

/** API側の元素表記 → アプリ内部の表記 */
const ELEMENT_MAP: Record<string, string> = {
  Fire: "pyro",
  Water: "hydro",
  Electric: "electro",
  Ice: "cryo",
  Wind: "anemo",
  Rock: "geo",
  Grass: "dendro",
};

/** 元素 → 旅人の表示名用ラベル */
const ELEMENT_LABEL: Record<string, string> = {
  pyro: "炎",
  hydro: "水",
  electro: "雷",
  cryo: "氷",
  anemo: "風",
  geo: "岩",
  dendro: "草",
};

/** API側の武器種表記 → アプリ内部の表記 */
const WEAPON_TYPE_MAP: Record<string, string> = {
  WEAPON_SWORD_ONE_HAND: "sword",
  WEAPON_CLAYMORE: "claymore",
  WEAPON_POLE: "polearm",
  WEAPON_BOW: "bow",
  WEAPON_CATALYST: "catalyst",
};

/** API側の地域表記 → 日本語表示名 */
const REGION_MAP: Record<string, string> = {
  MONDSTADT: "モンド",
  LIYUE: "璃月",
  INAZUMA: "稲妻",
  SUMERU: "スメール",
  FONTAINE: "フォンテーヌ",
  NATLAN: "ナタ",
  NODKRAI: "ノド・クライ",
  FATUI: "ファデュイ",
  MAINACTOR: "旅人",
};

/** 同期対象とする素材カテゴリ（育成に関係するもののみ） */
const MATERIAL_CATEGORIES = new Set([
  "characterLevelUpMaterial",
  "characterAscensionMaterial",
  "characterTalentMaterial",
  "characterEXPMaterial",
  "characterandWeaponEnhancementMaterial",
  "weaponAscensionMaterial",
  "weaponEnhancementMaterial",
  "localSpecialtyMondstadt",
  "localSpecialtyLiyue",
  "localSpecialtyInazuma",
  "localSpecialtySumeru",
  "localSpecialtyFontaine",
  "localSpecialtyNatlan",
  "localSpecialtyNodKrai",
]);

/** /avatar のレスポンス1件分（必要な項目のみ定義） */
interface AmberAvatar {
  id: number | string;
  name: string;
  rank: number;
  element: string | null;
  weaponType: string;
  region: string;
  icon: string;
  specialProp?: string;
}

/** /weapon のレスポンス1件分 */
interface AmberWeapon {
  id: number;
  name: string;
  rank: number;
  type: string;
  icon: string;
}

/** /material のレスポンス1件分 */
interface AmberMaterial {
  id: number;
  name: string;
  type: string;
  rank: number | null;
  icon: string;
}

/** タイムアウト付きでJSONを取得する共通ヘルパー */
async function fetchItems<T>(path: string): Promise<Record<string, T>> {
  const json = await fetchJsonObject(`${BASE_URL}${path}`, {
    timeoutMs: 30_000,
    maxBytes: 8 * 1024 * 1024,
    retries: 2,
    revalidateSeconds: 3600,
  });
  const data = json.data;
  if (
    json.response !== 200 ||
    !isRecord(data) ||
    !isRecord(data.items) ||
    Object.keys(data.items).length === 0
  ) {
    throw new UpstreamFetchError("invalidData");
  }
  return data.items as Record<string, T>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireUniqueId(
  ids: Set<string>,
  id: unknown,
): string {
  if (
    (typeof id !== "string" && typeof id !== "number") ||
    String(id).trim() === "" ||
    ids.has(String(id))
  ) {
    throw new UpstreamFetchError("invalidData");
  }
  const normalized = String(id);
  ids.add(normalized);
  return normalized;
}

/** アイコン名から画像URLを組み立てる */
function iconUrl(icon: string): string {
  return `${ASSET_URL}/${icon}.png`;
}

export const projectAmberProvider: GameDataProvider = {
  name: "Project Amber (gi.yatta.moe)",

  async fetchCharacters(): Promise<MasterCharacter[]> {
    const items = await fetchItems<AmberAvatar>("/api/v2/jp/avatar");
    const characters: MasterCharacter[] = [];
    const ids = new Set<string>();

    for (const avatar of Object.values(items)) {
      if (
        !isRecord(avatar) ||
        typeof avatar.name !== "string" ||
        avatar.name.trim() === "" ||
        (avatar.rank !== 4 && avatar.rank !== 5) ||
        (avatar.element !== null && typeof avatar.element !== "string") ||
        typeof avatar.weaponType !== "string" ||
        typeof avatar.region !== "string" ||
        typeof avatar.icon !== "string"
      ) {
        throw new UpstreamFetchError("invalidData");
      }
      const id = requireUniqueId(ids, avatar.id);
      // element が null のデータ（未実装のドール等）は除外
      const element = avatar.element ? ELEMENT_MAP[avatar.element] : undefined;
      if (!element || !avatar.name) continue;

      // 旅人は男女×元素で重複するため、男主人公（10000005）側だけを
      // 「旅人（風）」のような名前で登録する
      if (id.startsWith("10000007-")) continue;
      const isTraveler = id.startsWith("10000005-");
      const name = isTraveler
        ? `旅人（${ELEMENT_LABEL[element]}）`
        : avatar.name;

      characters.push({
        id,
        name,
        element,
        weaponType: WEAPON_TYPE_MAP[avatar.weaponType] ?? "sword",
        rarity: avatar.rank === 4 ? 4 : 5,
        region: REGION_MAP[avatar.region] ?? avatar.region,
        iconUrl: iconUrl(avatar.icon),
        scoreType: inferScoreType(avatar.specialProp, name),
      });
    }

    if (characters.length === 0) {
      throw new UpstreamFetchError("invalidData");
    }
    return characters;
  },

  async fetchWeapons(): Promise<MasterWeapon[]> {
    const items = await fetchItems<AmberWeapon>("/api/v2/jp/weapon");
    const ids = new Set<string>();
    const weapons = Object.values(items).map((weapon) => {
      if (
        !isRecord(weapon) ||
        typeof weapon.name !== "string" ||
        weapon.name.trim() === "" ||
        !Number.isInteger(weapon.rank) ||
        weapon.rank < 1 ||
        weapon.rank > 5 ||
        typeof weapon.type !== "string" ||
        typeof weapon.icon !== "string"
      ) {
        throw new UpstreamFetchError("invalidData");
      }
      return {
        id: requireUniqueId(ids, weapon.id),
        name: weapon.name,
        weaponType: WEAPON_TYPE_MAP[weapon.type] ?? "sword",
        rarity: weapon.rank,
        iconUrl: iconUrl(weapon.icon),
      };
    });
    if (weapons.length === 0) {
      throw new UpstreamFetchError("invalidData");
    }
    return weapons;
  },

  async fetchMaterials(): Promise<MasterMaterial[]> {
    const items = await fetchItems<AmberMaterial>("/api/v2/jp/material");
    const ids = new Set<string>();
    const materials: MasterMaterial[] = [];
    for (const material of Object.values(items)) {
      if (
        !isRecord(material) ||
        typeof material.name !== "string" ||
        material.name.trim() === "" ||
        typeof material.type !== "string" ||
        (material.rank !== null &&
          (!Number.isInteger(material.rank) ||
            material.rank < 1 ||
            material.rank > 5)) ||
        typeof material.icon !== "string"
      ) {
        throw new UpstreamFetchError("invalidData");
      }
      const id = requireUniqueId(ids, material.id);
      if (!MATERIAL_CATEGORIES.has(material.type)) continue;
      materials.push({
        id,
        name: material.name,
        category: material.type,
        rarity: material.rank,
        iconUrl: iconUrl(material.icon),
      });
    }
    if (materials.length === 0) {
      throw new UpstreamFetchError("invalidData");
    }
    return materials;
  },
};
