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

export interface SyncResult {
  provider: string;
  characters: number;
  weapons: number;
  materials: number;
  errors: string[];
}

/** マスターデータを外部APIからDBへ同期する */
export async function syncMasterData(): Promise<SyncResult> {
  const result: SyncResult = {
    provider: gameDataProvider.name,
    characters: 0,
    weapons: 0,
    materials: 0,
    errors: [],
  };

  // 3種類のデータを並列取得。1種類が失敗しても他は同期を続行する
  const [charactersRes, weaponsRes, materialsRes] = await Promise.allSettled([
    gameDataProvider.fetchCharacters(),
    gameDataProvider.fetchWeapons(),
    gameDataProvider.fetchMaterials(),
  ]);

  if (charactersRes.status === "fulfilled") {
    for (const c of charactersRes.value) {
      await prisma.character.upsert({
        where: { id: c.id },
        create: c,
        update: c,
      });
    }
    // プロバイダー変更などでAPIに存在しなくなったデータを削除する。
    // ただしユーザーの育成データが紐づいているキャラは残す（データ保護）
    await prisma.character.deleteMany({
      where: {
        id: { notIn: charactersRes.value.map((c) => c.id) },
        progresses: { none: {} },
      },
    });
    result.characters = charactersRes.value.length;
  } else {
    result.errors.push(`characters: ${String(charactersRes.reason)}`);
  }

  if (weaponsRes.status === "fulfilled") {
    for (const w of weaponsRes.value) {
      await prisma.weapon.upsert({
        where: { id: w.id },
        create: w,
        update: w,
      });
    }
    await prisma.weapon.deleteMany({
      where: { id: { notIn: weaponsRes.value.map((w) => w.id) } },
    });
    result.weapons = weaponsRes.value.length;
  } else {
    result.errors.push(`weapons: ${String(weaponsRes.reason)}`);
  }

  if (materialsRes.status === "fulfilled") {
    for (const m of materialsRes.value) {
      await prisma.material.upsert({
        where: { id: m.id },
        create: m,
        update: m,
      });
    }
    await prisma.material.deleteMany({
      where: { id: { notIn: materialsRes.value.map((m) => m.id) } },
    });
    result.materials = materialsRes.value.length;
  } else {
    result.errors.push(`materials: ${String(materialsRes.reason)}`);
  }

  // 同期履歴を残す（Cron監視・デバッグ用）
  await prisma.syncLog.create({
    data: {
      status: result.errors.length === 0 ? "success" : "error",
      detail: JSON.stringify(result),
    },
  });

  return result;
}
