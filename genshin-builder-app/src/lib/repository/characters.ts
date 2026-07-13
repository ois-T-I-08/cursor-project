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

/** IDからキャラクターを1体取得する（見つからなければ null）。
 *  DB接続エラーは再スローし、呼び出し側でエラーバウンダリに任せる。
 */
export async function getCharacter(id: string): Promise<Character | null> {
  try {
    const row = await prisma.character.findUnique({ where: { id } });
    if (row) return toCharacter(row);
  } catch (error) {
    if (error instanceof Error && error.message.includes("Can't reach database")) {
      throw error;
    }
    console.error("キャラクターのDB取得に失敗しました:", error);
    throw error;
  }
  return DUMMY_CHARACTERS.find((c) => c.id === id) ?? null;
}

/** マスターデータの件数（設定画面の表示用） */
export async function getMasterDataCounts(): Promise<{
  characters: number;
  weapons: number;
  materials: number;
  characterUpgrades: number;
  weaponUpgrades: number;
  levelExpSegments: number;
  lastSyncedAt: Date | null;
}> {
  try {
    const [
      characters,
      weapons,
      materials,
      characterUpgrades,
      weaponUpgrades,
      levelExpSegments,
      lastLog,
    ] = await Promise.all([
      prisma.character.count(),
      prisma.weapon.count(),
      prisma.material.count(),
      prisma.characterUpgrade.count(),
      prisma.weaponUpgrade.count(),
      prisma.levelExpSegment.count(),
      prisma.syncLog.findFirst({
        where: { status: "success" },
        orderBy: { createdAt: "desc" },
      }),
    ]);
    return {
      characters,
      weapons,
      materials,
      characterUpgrades,
      weaponUpgrades,
      levelExpSegments,
      lastSyncedAt: lastLog?.createdAt ?? null,
    };
  } catch {
    return {
      characters: 0,
      weapons: 0,
      materials: 0,
      characterUpgrades: 0,
      weaponUpgrades: 0,
      levelExpSegments: 0,
      lastSyncedAt: null,
    };
  }
}

/** 同期状態（設定画面の案内・不足検知用） */
export interface SyncStatus {
  characters: number;
  weapons: number;
  materials: number;
  characterUpgrades: number;
  weaponUpgrades: number;
  levelExpSegments: number;
  lastSyncedAt: Date | null;
  missingCharacterUpgrades: number;
  missingWeaponUpgrades: number;
  /** 突破・EXP表が揃っている */
  upgradeComplete: boolean;
  /** マスタ未同期（初回） */
  isUnsynced: boolean;
  /** 初回の突破取得（通常同期で全件取る必要あり） */
  needsInitialUpgradeSync: boolean;
}

export async function getSyncStatus(): Promise<SyncStatus> {
  const counts = await getMasterDataCounts();
  const missingCharacterUpgrades = Math.max(
    0,
    counts.characters - counts.characterUpgrades,
  );
  const missingWeaponUpgrades = Math.max(
    0,
    counts.weapons - counts.weaponUpgrades,
  );
  const expTableReady = counts.levelExpSegments >= 32;

  return {
    ...counts,
    missingCharacterUpgrades,
    missingWeaponUpgrades,
    upgradeComplete:
      missingCharacterUpgrades === 0 &&
      missingWeaponUpgrades === 0 &&
      expTableReady,
    isUnsynced: counts.characters === 0,
    needsInitialUpgradeSync:
      counts.characters > 0 && counts.characterUpgrades === 0,
  };
}
