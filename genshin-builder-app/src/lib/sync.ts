/**
 * マスターデータ同期処理
 *
 * 外部API → DB へキャラクター・武器・素材を登録・更新（upsert）する。
 * APIが一時的に落ちていてもDB内の既存データはそのまま残るため、
 * アプリはDBのデータで動作し続けられる。
 *
 * 将来的には Vercel Cron などからこの関数を定期実行する想定。
 */

import { gameDataProvider } from "@/lib/api";
import { prisma } from "@/lib/db";
import { UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import {
  SyncLeaseOwnershipLostError,
  throwIfSyncAborted,
} from "@/lib/sync-distributed-lock";
import { syncUpgradeData, type UpgradeSyncOptions } from "@/lib/sync-upgrade";
import {
  forEachBatch,
  idsForNotIn,
  UPSERT_BATCH_SIZE,
} from "@/lib/sync-utils";

export type SyncOptions = UpgradeSyncOptions;

export interface SyncResult {
  provider: string;
  characters: number;
  weapons: number;
  materials: number;
  characterUpgrades: number;
  weaponUpgrades: number;
  levelExpSegments: number;
  expMaterials: number;
  upgradeApiCalls: number;
  skippedCharacterUpgrades: number;
  skippedWeaponUpgrades: number;
  errors: string[];
}

/** マスターデータを外部APIからDBへ同期する */
export async function syncMasterData(
  options: SyncOptions = {},
): Promise<SyncResult> {
  const signal = options.signal;
  throwIfSyncAborted(signal);

  const result: SyncResult = {
    provider: gameDataProvider.name,
    characters: 0,
    weapons: 0,
    materials: 0,
    characterUpgrades: 0,
    weaponUpgrades: 0,
    levelExpSegments: 0,
    expMaterials: 0,
    upgradeApiCalls: 0,
    skippedCharacterUpgrades: 0,
    skippedWeaponUpgrades: 0,
    errors: [],
  };

  // 3種類のデータを並列取得。1種類が失敗しても他は同期を続行する
  const [charactersRes, weaponsRes, materialsRes] = await Promise.allSettled([
    gameDataProvider.fetchCharacters(),
    gameDataProvider.fetchWeapons(),
    gameDataProvider.fetchMaterials(),
  ]);

  throwIfSyncAborted(signal);

  if (charactersRes.status === "fulfilled") {
    throwIfSyncAborted(signal);
    await prisma.$transaction(
      async (tx) => {
        await forEachBatch(
          charactersRes.value,
          UPSERT_BATCH_SIZE,
          async (batch) => {
            throwIfSyncAborted(signal);
            await Promise.all(
              batch.map((c) =>
                tx.character.upsert({
                  where: { id: c.id },
                  create: c,
                  update: c,
                }),
              ),
            );
          },
        );
        const characterIds = charactersRes.value.map((c) => c.id);
        const excludeIds = idsForNotIn(characterIds);
        if (excludeIds) {
          throwIfSyncAborted(signal);
          await tx.character.deleteMany({
            where: {
              id: { notIn: excludeIds },
              progresses: { none: {} },
            },
          });
        }
      },
      { timeout: 30_000 },
    );
    result.characters = charactersRes.value.length;
  } else {
    result.errors.push(syncErrorCode("characters", charactersRes.reason));
  }

  throwIfSyncAborted(signal);

  if (weaponsRes.status === "fulfilled") {
    throwIfSyncAborted(signal);
    await prisma.$transaction(
      async (tx) => {
        await forEachBatch(
          weaponsRes.value,
          UPSERT_BATCH_SIZE,
          async (batch) => {
            throwIfSyncAborted(signal);
            await Promise.all(
              batch.map((weapon) =>
                tx.weapon.upsert({
                  where: { id: weapon.id },
                  create: weapon,
                  update: weapon,
                }),
              ),
            );
          },
        );
        const weaponIds = weaponsRes.value.map((weapon) => weapon.id);
        const referencedWeaponIds = (
          await tx.userProgress.findMany({
            where: { weaponId: { not: "" } },
            select: { weaponId: true },
            distinct: ["weaponId"],
          })
        ).map((row) => row.weaponId);
        const keepWeaponIds = [
          ...new Set([...weaponIds, ...referencedWeaponIds]),
        ];
        const excludeWeaponIds = idsForNotIn(keepWeaponIds);
        if (excludeWeaponIds) {
          throwIfSyncAborted(signal);
          await tx.weapon.deleteMany({
            where: { id: { notIn: excludeWeaponIds } },
          });
        }
      },
      { timeout: 30_000 },
    );
    result.weapons = weaponsRes.value.length;
  } else {
    result.errors.push(syncErrorCode("weapons", weaponsRes.reason));
  }

  throwIfSyncAborted(signal);

  if (materialsRes.status === "fulfilled") {
    throwIfSyncAborted(signal);
    await prisma.$transaction(
      async (tx) => {
        await forEachBatch(
          materialsRes.value,
          UPSERT_BATCH_SIZE,
          async (batch) => {
            throwIfSyncAborted(signal);
            await Promise.all(
              batch.map((material) =>
                tx.material.upsert({
                  where: { id: material.id },
                  create: material,
                  update: material,
                }),
              ),
            );
          },
        );
        const materialIds = materialsRes.value.map((material) => material.id);
        const excludeMaterialIds = idsForNotIn(materialIds);
        if (excludeMaterialIds) {
          throwIfSyncAborted(signal);
          await tx.material.deleteMany({
            where: { id: { notIn: excludeMaterialIds } },
          });
        }
      },
      { timeout: 30_000 },
    );
    result.materials = materialsRes.value.length;
  } else {
    result.errors.push(syncErrorCode("materials", materialsRes.reason));
  }

  throwIfSyncAborted(signal);

  // 突破・天賦・EXP（差分同期。fullUpgrade で全件再取得）
  const upgradeRes = await syncUpgradeData(options);
  result.characterUpgrades = upgradeRes.characterUpgrades;
  result.weaponUpgrades = upgradeRes.weaponUpgrades;
  result.levelExpSegments = upgradeRes.levelExpSegments;
  result.expMaterials = upgradeRes.expMaterials;
  result.upgradeApiCalls = upgradeRes.apiCalls;
  result.skippedCharacterUpgrades = upgradeRes.skippedCharacterUpgrades;
  result.skippedWeaponUpgrades = upgradeRes.skippedWeaponUpgrades;
  result.errors.push(...upgradeRes.errors);

  throwIfSyncAborted(signal);

  // 同期履歴を残す（Cron監視・デバッグ用）
  await prisma.syncLog.create({
    data: {
      status: result.errors.length === 0 ? "success" : "error",
      detail: JSON.stringify(result),
    },
  });

  return result;
}

function syncErrorCode(phase: string, error: unknown): string {
  if (error instanceof SyncLeaseOwnershipLostError) {
    throw error;
  }
  const code =
    error instanceof UpstreamFetchError ? error.code : "unavailable";
  return `${phase}:${code}`;
}
