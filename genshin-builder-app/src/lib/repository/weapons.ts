/**
 * 武器マスターデータのリポジトリ（DB読み取り層）
 */

import { prisma } from "@/lib/db";

export interface WeaponOption {
  id: string;
  name: string;
  rarity: number;
  iconUrl: string;
}

/**
 * 指定した武器種の武器一覧を取得する（育成フォームの選択肢用）。
 * レアリティの高い順・名前順で返す。
 */
export async function getWeaponsByType(
  weaponType: string,
): Promise<WeaponOption[]> {
  try {
    return await prisma.weapon.findMany({
      where: { weaponType, rarity: { gte: 3 } },
      select: { id: true, name: true, rarity: true, iconUrl: true },
      orderBy: [{ rarity: "desc" }, { name: "asc" }],
    });
  } catch (error) {
    console.error("武器のDB取得に失敗しました:", error);
    return [];
  }
}
