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

/** APIの共通レスポンス形式 */
interface AmberResponse<T> {
  response: number;
  data: T;
}

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
  const res = await fetch(`${BASE_URL}${path}`, {
    // マスターデータは頻繁に変わらないため、Next.js のキャッシュを1時間有効にする
    next: { revalidate: 3600 },
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) {
    throw new Error(`API request failed: ${path} (${res.status})`);
  }
  const json = (await res.json()) as AmberResponse<{ items: Record<string, T> }>;
  return json.data.items;
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

    for (const avatar of Object.values(items)) {
      // element が null のデータ（未実装のドール等）は除外
      const element = avatar.element ? ELEMENT_MAP[avatar.element] : undefined;
      if (!element || !avatar.name) continue;

      const id = String(avatar.id);

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

    return characters;
  },

  async fetchWeapons(): Promise<MasterWeapon[]> {
    const items = await fetchItems<AmberWeapon>("/api/v2/jp/weapon");

    return Object.values(items)
      .filter((w) => w.name)
      .map((w) => ({
        id: String(w.id),
        name: w.name,
        weaponType: WEAPON_TYPE_MAP[w.type] ?? "sword",
        rarity: w.rank,
        iconUrl: iconUrl(w.icon),
      }));
  },

  async fetchMaterials(): Promise<MasterMaterial[]> {
    const items = await fetchItems<AmberMaterial>("/api/v2/jp/material");

    return Object.values(items)
      .filter((m) => m.name && MATERIAL_CATEGORIES.has(m.type))
      .map((m) => ({
        id: String(m.id),
        name: m.name,
        category: m.type,
        rarity: m.rank ?? null,
        iconUrl: iconUrl(m.icon),
      }));
  },
};
