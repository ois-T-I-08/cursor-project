/**
 * フォールバック用ダミーデータ
 *
 * DBが空（初回同期前）またはDB障害時に、画面が壊れないよう
 * 最低限のキャラクター一覧を表示するために使う。
 * 通常はDBに同期されたマスターデータが使われる。
 */

import type { Character } from "@/types/character";

export const DUMMY_CHARACTERS: Character[] = [
  { id: "hu-tao", name: "胡桃", element: "pyro", weaponType: "polearm", rarity: 5, region: "璃月", emoji: "🌸" },
  { id: "raiden-shogun", name: "雷電将軍", element: "electro", weaponType: "polearm", rarity: 5, region: "稲妻", emoji: "⚡" },
  { id: "kazuha", name: "楓原万葉", element: "anemo", weaponType: "sword", rarity: 5, region: "稲妻", emoji: "🍁" },
  { id: "zhongli", name: "鍾離", element: "geo", weaponType: "polearm", rarity: 5, region: "璃月", emoji: "🪨" },
  { id: "furina", name: "フリーナ", element: "hydro", weaponType: "sword", rarity: 5, region: "フォンテーヌ", emoji: "🎭" },
  { id: "nahida", name: "ナヒーダ", element: "dendro", weaponType: "catalyst", rarity: 5, region: "スメール", emoji: "🌱" },
  { id: "ayaka", name: "神里綾華", element: "cryo", weaponType: "sword", rarity: 5, region: "稲妻", emoji: "👘" },
  { id: "bennett", name: "ベネット", element: "pyro", weaponType: "sword", rarity: 4, region: "モンド", emoji: "✨" },
  { id: "xingqiu", name: "行秋", element: "hydro", weaponType: "sword", rarity: 4, region: "璃月", emoji: "📚" },
  { id: "xiangling", name: "香菱", element: "pyro", weaponType: "polearm", rarity: 4, region: "璃月", emoji: "🍳" },
];
