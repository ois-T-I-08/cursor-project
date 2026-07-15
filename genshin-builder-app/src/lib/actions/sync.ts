"use server";

/**
 * マスターデータ同期 Server Action
 *
 * 設定画面の同期ボタンから呼ばれる。Cron API と同じ秘密・排他制御を使う。
 */

import { revalidatePath } from "next/cache";
import type { SyncResult } from "@/lib/sync";
import { verifySyncActionSecret } from "@/lib/sync-auth";
import {
  runSyncExclusive,
  SyncAlreadyRunningError,
} from "@/lib/sync-execution";

export type SyncActionResult = SyncResult & {
  ok: boolean;
  message?: string;
};

/** マスターデータを外部 API から DB へ同期する */
export async function syncMasterDataAction(
  fullUpgrade = false,
  secret?: string,
): Promise<SyncActionResult> {
  if (!verifySyncActionSecret(secret)) {
    return failedResult("認証に失敗しました。");
  }

  try {
    const result = await runSyncExclusive(fullUpgrade);
    revalidatePath("/characters");
    revalidatePath("/settings");
    return {
      ok: result.errors.length === 0,
      ...result,
    };
  } catch (error) {
    if (error instanceof SyncAlreadyRunningError) {
      return failedResult("同期は既に実行中です。完了後に再度お試しください。");
    }
    console.error("マスターデータ同期に失敗しました:", error);
    return failedResult("同期に失敗しました。時間をおいて再度お試しください。");
  }
}

function failedResult(message: string): SyncActionResult {
  return {
    ok: false,
    message,
    provider: "",
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
}
