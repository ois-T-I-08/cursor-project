/**
 * 使用するデータ取得プロバイダーの選択。
 * 別のAPIへ移行する場合は、GameDataProvider を実装して
 * 以下の1行を差し替えるだけでよい。
 *
 * genshin.jmp.blue 版（genshin-jmp-blue.ts）はデータ更新が停止しているため、
 * 最新キャラまで収録され日本語名も取得できる Project Amber を使用する。
 */

import { projectAmberProvider } from "./project-amber";
import type { GameDataProvider } from "./types";

export const gameDataProvider: GameDataProvider = projectAmberProvider;

export type {
  GameDataProvider,
  MasterCharacter,
  MasterMaterial,
  MasterWeapon,
} from "./types";
