/**
 * 育成入力の制限値・選択肢
 * 画面（Client）と保存処理（Server Action）の両方から参照する。
 */

export {
  LEVEL_MARKS,
  LEVEL_MAX as CHARACTER_LEVEL_MAX,
  LEVEL_DISPLAY_MAX as CHARACTER_LEVEL_DISPLAY_MAX,
  TALENT_LEVEL_MAX,
} from "./level-config";

export { clampInt, snapToLevelMark as snapWeaponLevel } from "./level-progression";

import { TALENT_LEVEL_MAX } from "./level-config";

/** @deprecated snapWeaponLevel を使用 */
export const WEAPON_LEVEL_OPTIONS = [1, 20, 30, 40, 50, 60, 70, 80, 90] as const;

/**
 * 天賦レベルの上限を返す。
 * 将来、命ノ星座で+3（最大Lv.13）に対応する場合は constellation を参照する。
 */
export function getTalentLevelMax(constellation = 0): number {
  // TODO: 特定凸で +3 する場合はここで constellation を判定
  void constellation;
  return TALENT_LEVEL_MAX;
}
