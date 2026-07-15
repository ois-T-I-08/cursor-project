/**
 * 突破・天賦・レベルEXPデータの同期
 *
 * 通常同期: マスタ一覧 + DB に未登録の突破データのみ API 取得（差分）
 * 完全同期: 全キャラ・武器の detail API を再取得し、1 トランザクションで置換
 */

import {
  buildLevelExpSegments,
  fetchCharacterUpgradeFromApi,
  fetchLevelUpMaterialsFromApi,
  fetchWeaponUpgradeFromApi,
  mapWithConcurrency,
} from "@/lib/api/amber-upgrade";
import type {
  CharacterUpgradeData,
  LevelExpSegmentData,
  LevelUpMaterialData,
  WeaponUpgradeData,
} from "@/lib/api/upgrade-types";
import { UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import { prisma } from "@/lib/db";
import { idsForNotIn } from "@/lib/sync-utils";

const EXP_MATERIAL_COUNT = 6;
const LEVEL_EXP_SEGMENT_COUNT = 32;
const CONCURRENCY = 4;
const REQUEST_DELAY_MS = 100;

export interface UpgradeSyncOptions {
  /** true なら全件 detail API を再取得 */
  fullUpgrade?: boolean;
}

export interface UpgradeSyncResult {
  characterUpgrades: number;
  weaponUpgrades: number;
  levelExpSegments: number;
  expMaterials: number;
  /** 今回 API を叩いた回数（目安） */
  apiCalls: number;
  skippedCharacterUpgrades: number;
  skippedWeaponUpgrades: number;
  errors: string[];
}

function trackApiCall(counter: { count: number }): void {
  counter.count += 1;
}

async function delay(ms: number): Promise<void> {
  if (ms <= 0) return;
  await new Promise((resolve) => setTimeout(resolve, ms));
}

/** 突破・天賦・EXPデータをAPIからDBへ同期 */
export async function syncUpgradeData(
  options: UpgradeSyncOptions = {},
): Promise<UpgradeSyncResult> {
  const fullUpgrade = options.fullUpgrade ?? false;
  if (fullUpgrade) {
    return syncUpgradeDataFull();
  }
  return syncUpgradeDataIncremental();
}

async function syncUpgradeDataFull(): Promise<UpgradeSyncResult> {
  const apiCounter = { count: 0 };
  const result = emptyUpgradeResult();

  try {
    const levelUpMaterials = await fetchLevelUpMaterialsFromApi(() =>
      trackApiCall(apiCounter),
    );
    const segments = buildLevelExpSegments();

    const [allCharacters, allWeapons] = await Promise.all([
      prisma.character.findMany({ select: { id: true } }),
      prisma.weapon.findMany({ select: { id: true } }),
    ]);

    const characterTargetIds = allCharacters.map((character) => character.id);
    const weaponTargetIds = allWeapons.map((weapon) => weapon.id);

    const characterUpgrades = await mapWithConcurrency(
      characterTargetIds,
      CONCURRENCY,
      async (characterId) => {
        await delay(REQUEST_DELAY_MS);
        trackApiCall(apiCounter);
        return fetchCharacterUpgradeFromApi(characterId);
      },
    );

    const weaponUpgrades = await mapWithConcurrency(
      weaponTargetIds,
      CONCURRENCY,
      async (weaponId) => {
        await delay(REQUEST_DELAY_MS);
        trackApiCall(apiCounter);
        return fetchWeaponUpgradeFromApi(weaponId);
      },
    );

    await prisma.$transaction(
      async (tx) => {
        await applyExpMaterials(tx, levelUpMaterials);
        await applyLevelExpSegments(tx, segments);
        await applyCharacterUpgrades(tx, characterUpgrades, {
          pruneMissing: true,
        });
        await applyWeaponUpgrades(tx, weaponUpgrades, { pruneMissing: true });
      },
      { timeout: 60_000 },
    );

    result.expMaterials = levelUpMaterials.length;
    result.levelExpSegments = segments.length;
    result.characterUpgrades = await prisma.characterUpgrade.count();
    result.weaponUpgrades = await prisma.weaponUpgrade.count();
    result.skippedCharacterUpgrades = 0;
    result.skippedWeaponUpgrades = 0;
  } catch (error) {
    result.errors.push(upgradeErrorCode("fullUpgrade", error));
    result.characterUpgrades = await prisma.characterUpgrade.count();
    result.weaponUpgrades = await prisma.weaponUpgrade.count();
    result.levelExpSegments = await prisma.levelExpSegment.count();
    const existingExpMaterials = await prisma.material.count({
      where: { expValue: { not: null }, expTarget: { not: null } },
    });
    result.expMaterials = existingExpMaterials;
  }

  result.apiCalls = apiCounter.count;
  return result;
}

async function syncUpgradeDataIncremental(): Promise<UpgradeSyncResult> {
  const apiCounter = { count: 0 };
  const result = emptyUpgradeResult();

  // 1. 経験値素材（API material detail）— 未設定時のみ
  try {
    const existingExpMaterials = await prisma.material.count({
      where: { expValue: { not: null }, expTarget: { not: null } },
    });

    if (existingExpMaterials < EXP_MATERIAL_COUNT) {
      const levelUpMaterials = await fetchLevelUpMaterialsFromApi(() =>
        trackApiCall(apiCounter),
      );
      await prisma.$transaction(
        levelUpMaterials.map((material) =>
          prisma.material.updateMany({
            where: { id: material.materialId },
            data: {
              expValue: material.exp,
              expTarget: material.targetType,
            },
          }),
        ),
      );
      result.expMaterials = levelUpMaterials.length;
    } else {
      result.expMaterials = existingExpMaterials;
    }
  } catch (error) {
    result.errors.push(upgradeErrorCode("expMaterials", error));
  }

  // 2. 目盛り間EXP（API なし・定数）— 未登録時のみ書き込み
  try {
    const existingSegments = await prisma.levelExpSegment.count();
    if (existingSegments < LEVEL_EXP_SEGMENT_COUNT) {
      const segments = buildLevelExpSegments();
      await prisma.$transaction(
        segments.map((segment) =>
          prisma.levelExpSegment.upsert({
            where: { id: segment.id },
            create: segment,
            update: {
              expRequired: segment.expRequired,
              moraRequired: segment.moraRequired,
            },
          }),
        ),
      );
      result.levelExpSegments = segments.length;
    } else {
      result.levelExpSegments = existingSegments;
    }
  } catch (error) {
    result.errors.push(upgradeErrorCode("levelExpSegments", error));
  }

  // 3. キャラクター突破・天賦
  try {
    const [allCharacters, existingUpgrades] = await Promise.all([
      prisma.character.findMany({ select: { id: true } }),
      prisma.characterUpgrade.findMany({ select: { characterId: true } }),
    ]);

    const existingIds = new Set(existingUpgrades.map((u) => u.characterId));
    const targetIds = allCharacters
      .filter((character) => !existingIds.has(character.id))
      .map((character) => character.id);

    result.skippedCharacterUpgrades = allCharacters.length - targetIds.length;

    if (targetIds.length > 0) {
      const upgrades = await mapWithConcurrency(
        targetIds,
        CONCURRENCY,
        async (characterId) => {
          await delay(REQUEST_DELAY_MS);
          trackApiCall(apiCounter);
          return fetchCharacterUpgradeFromApi(characterId);
        },
      );

      await prisma.$transaction(
        async (tx) => {
          await applyCharacterUpgrades(tx, upgrades, { pruneMissing: false });
        },
        { timeout: 30_000 },
      );
    }

    result.characterUpgrades = await prisma.characterUpgrade.count();
  } catch (error) {
    result.errors.push(upgradeErrorCode("characterUpgrades", error));
  }

  // 4. 武器突破
  try {
    const [allWeapons, existingUpgrades] = await Promise.all([
      prisma.weapon.findMany({ select: { id: true } }),
      prisma.weaponUpgrade.findMany({ select: { weaponId: true } }),
    ]);

    const existingIds = new Set(existingUpgrades.map((u) => u.weaponId));
    const targetIds = allWeapons
      .filter((weapon) => !existingIds.has(weapon.id))
      .map((weapon) => weapon.id);

    result.skippedWeaponUpgrades = allWeapons.length - targetIds.length;

    if (targetIds.length > 0) {
      const upgrades = await mapWithConcurrency(
        targetIds,
        CONCURRENCY,
        async (weaponId) => {
          await delay(REQUEST_DELAY_MS);
          trackApiCall(apiCounter);
          return fetchWeaponUpgradeFromApi(weaponId);
        },
      );

      await prisma.$transaction(
        async (tx) => {
          await applyWeaponUpgrades(tx, upgrades, { pruneMissing: false });
        },
        { timeout: 30_000 },
      );
    }

    result.weaponUpgrades = await prisma.weaponUpgrade.count();
  } catch (error) {
    result.errors.push(upgradeErrorCode("weaponUpgrades", error));
  }

  result.apiCalls = apiCounter.count;
  return result;
}

type UpgradeTransaction = Parameters<
  Parameters<typeof prisma.$transaction>[0]
>[0];

async function applyExpMaterials(
  tx: UpgradeTransaction,
  materials: LevelUpMaterialData[],
): Promise<void> {
  for (const material of materials) {
    await tx.material.updateMany({
      where: { id: material.materialId },
      data: {
        expValue: material.exp,
        expTarget: material.targetType,
      },
    });
  }
}

async function applyLevelExpSegments(
  tx: UpgradeTransaction,
  segments: LevelExpSegmentData[],
): Promise<void> {
  for (const segment of segments) {
    await tx.levelExpSegment.upsert({
      where: { id: segment.id },
      create: segment,
      update: {
        expRequired: segment.expRequired,
        moraRequired: segment.moraRequired,
      },
    });
  }
}

async function applyCharacterUpgrades(
  tx: UpgradeTransaction,
  upgrades: CharacterUpgradeData[],
  options: { pruneMissing: boolean },
): Promise<void> {
  for (const upgrade of upgrades) {
    await tx.characterUpgrade.upsert({
      where: { characterId: upgrade.characterId },
      create: {
        characterId: upgrade.characterId,
        promotes: JSON.stringify(upgrade.promotes),
        talents: JSON.stringify(upgrade.talents),
      },
      update: {
        promotes: JSON.stringify(upgrade.promotes),
        talents: JSON.stringify(upgrade.talents),
      },
    });
  }

  if (!options.pruneMissing) return;

  const syncedIds = upgrades.map((upgrade) => upgrade.characterId);
  const excludeIds = idsForNotIn(syncedIds);
  if (!excludeIds) return;

  await tx.characterUpgrade.deleteMany({
    where: { characterId: { notIn: excludeIds } },
  });
}

async function applyWeaponUpgrades(
  tx: UpgradeTransaction,
  upgrades: WeaponUpgradeData[],
  options: { pruneMissing: boolean },
): Promise<void> {
  for (const upgrade of upgrades) {
    await tx.weaponUpgrade.upsert({
      where: { weaponId: upgrade.weaponId },
      create: {
        weaponId: upgrade.weaponId,
        promotes: JSON.stringify(upgrade.promotes),
        levelUpItemIds: JSON.stringify(upgrade.levelUpItemIds),
      },
      update: {
        promotes: JSON.stringify(upgrade.promotes),
        levelUpItemIds: JSON.stringify(upgrade.levelUpItemIds),
      },
    });
  }

  if (!options.pruneMissing) return;

  const syncedIds = upgrades.map((upgrade) => upgrade.weaponId);
  const excludeIds = idsForNotIn(syncedIds);
  if (!excludeIds) return;

  await tx.weaponUpgrade.deleteMany({
    where: { weaponId: { notIn: excludeIds } },
  });
}

function emptyUpgradeResult(): UpgradeSyncResult {
  return {
    characterUpgrades: 0,
    weaponUpgrades: 0,
    levelExpSegments: 0,
    expMaterials: 0,
    apiCalls: 0,
    skippedCharacterUpgrades: 0,
    skippedWeaponUpgrades: 0,
    errors: [],
  };
}

function upgradeErrorCode(phase: string, error: unknown): string {
  const code =
    error instanceof UpstreamFetchError ? error.code : "unavailable";
  return `${phase}:${code}`;
}
