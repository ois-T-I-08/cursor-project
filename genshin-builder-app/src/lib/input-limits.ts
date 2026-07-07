/**
 * 育成入力の制限値・選択肢
 * 画面（Client）と保存処理（Server Action）の両方から参照する。
 */

/** キャラクターレベルの上限 */
export const CHARACTER_LEVEL_MAX = 90;

/** 天賦レベルの上限（将来、命ノ星座+3で13まで拡張する場合は getTalentLevelMax を使う） */
export const TALENT_LEVEL_MAX = 10;

/** 武器レベルの選択肢（10刻み） */
export const WEAPON_LEVEL_OPTIONS = [1, 20, 30, 40, 50, 60, 70, 80, 90] as const;

/** 整数を min〜max に収める */
export function clampInt(value: unknown, min: number, max: number): number {
  const n = Math.round(Number(value));
  if (Number.isNaN(n)) return min;
  return Math.min(max, Math.max(min, n));
}

/** 武器レベルを許可された10刻みの値に丸める */
export function snapWeaponLevel(value: unknown): number {
  const n = clampInt(value, 1, CHARACTER_LEVEL_MAX);
  let closest: number = WEAPON_LEVEL_OPTIONS[0];
  let minDiff = Math.abs(n - closest);
  for (const level of WEAPON_LEVEL_OPTIONS) {
    const diff = Math.abs(n - level);
    if (diff < minDiff) {
      minDiff = diff;
      closest = level;
    }
  }
  return closest;
}

/**
 * 天賦レベルの上限を返す。
 * 将来、命ノ星座で+3（最大Lv.13）に対応する場合は constellation を参照する。
 */
export function getTalentLevelMax(_constellation = 0): number {
  // TODO: 特定凸で +3 する場合はここで constellation を判定
  return TALENT_LEVEL_MAX;
}
