/**
 * キャラクターマスターデータのリポジトリ（DB読み取り層）
 *
 * 画面側はこのモジュール経由でデータを取得する。
 * DBが空（初回同期前）の場合はダミーデータへフォールバックするため、
 * 外部APIが利用できない状態でもアプリは動作し続ける。
 */

import type { Character as DbCharacter } from "@prisma/client";
import { prisma } from "@/lib/db";
import { DUMMY_CHARACTERS } from "@/lib/dummy-data";
import type { Character, Element, Rarity, WeaponType } from "@/types/character";

const ELEMENTS: readonly Element[] = [
  "pyro",
  "hydro",
  "electro",
  "cryo",
  "anemo",
  "geo",
  "dendro",
];

const WEAPON_TYPES: readonly WeaponType[] = [
  "sword",
  "claymore",
  "polearm",
  "bow",
  "catalyst",
];

/** DBの行（文字列カラム）をアプリの型へ安全に変換する */
export function toCharacter(row: DbCharacter): Character {
  return {
    id: row.id,
    name: row.name,
    element: ELEMENTS.includes(row.element as Element)
      ? (row.element as Element)
      : "anemo",
    weaponType: WEAPON_TYPES.includes(row.weaponType as WeaponType)
      ? (row.weaponType as WeaponType)
      : "sword",
    rarity: (row.rarity === 4 ? 4 : 5) as Rarity,
    region: row.region,
    iconUrl: row.iconUrl,
    scoreType: row.scoreType,
  };
}

/**
 * 全キャラクターを取得する。
 * DBにデータがなければダミーデータを返す（初回同期前のフォールバック）。
 */
export async function getAllCharacters(): Promise<Character[]> {
  try {
    const rows = await prisma.character.findMany({
      orderBy: [{ rarity: "desc" }, { name: "asc" }],
    });
    if (rows.length > 0) {
      return rows.map(toCharacter);
    }
  } catch (error) {
    console.error("キャラクターのDB取得に失敗しました:", error);
  }
  return DUMMY_CHARACTERS;
}

/** IDからキャラクターを1体取得する（見つからなければ null） */
export async function getCharacter(id: string): Promise<Character | null> {
  try {
    const row = await prisma.character.findUnique({ where: { id } });
    if (row) return toCharacter(row);
  } catch (error) {
    console.error("キャラクターのDB取得に失敗しました:", error);
  }
  return DUMMY_CHARACTERS.find((c) => c.id === id) ?? null;
}

/** マスターデータの件数（設定画面の表示用） */
export async function getMasterDataCounts(): Promise<{
  characters: number;
  weapons: number;
  materials: number;
  lastSyncedAt: Date | null;
}> {
  try {
    const [characters, weapons, materials, lastLog] = await Promise.all([
      prisma.character.count(),
      prisma.weapon.count(),
      prisma.material.count(),
      prisma.syncLog.findFirst({
        where: { status: "success" },
        orderBy: { createdAt: "desc" },
      }),
    ]);
    return {
      characters,
      weapons,
      materials,
      lastSyncedAt: lastLog?.createdAt ?? null,
    };
  } catch {
    return { characters: 0, weapons: 0, materials: 0, lastSyncedAt: null };
  }
}
