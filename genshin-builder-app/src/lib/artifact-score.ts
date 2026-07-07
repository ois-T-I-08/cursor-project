/**
 * 聖遺物スコア計算
 *
 * キャラクターごとに「推奨スコア計算タイプ」を持ち、参照ステータスに応じて
 * 計算式を切り替える。新しい計算タイプを追加する場合は
 * SCORE_FORMULAS にエントリを足すだけでよい。
 *
 *   攻撃基準:   会心率×2 + 会心ダメージ + 攻撃力%
 *   HP基準:     会心率×2 + 会心ダメージ + HP%
 *   防御基準:   会心率×2 + 会心ダメージ + 防御力%
 *   熟知基準:   会心率×2 + 会心ダメージ + 元素熟知÷4
 */

import type {
  ArtifactPiece,
  ArtifactState,
  ArtifactSubstat,
} from "@/types/character";

export type ScoreType = "atk" | "hp" | "def" | "em";

export const SCORE_TYPE_LABEL: Record<ScoreType, string> = {
  atk: "攻撃力基準",
  hp: "HP基準",
  def: "防御力基準",
  em: "元素熟知基準",
};

/** タイプごとの「会心系以外」のスコア寄与計算 */
const SCORE_FORMULAS: Record<ScoreType, (sub: ArtifactSubstat) => number> = {
  atk: (sub) => (sub.stat === "攻撃力%" ? sub.value : 0),
  hp: (sub) => (sub.stat === "HP%" ? sub.value : 0),
  def: (sub) => (sub.stat === "防御力%" ? sub.value : 0),
  em: (sub) => (sub.stat === "元素熟知" ? sub.value / 4 : 0),
};

/**
 * キャラクター名 → 推奨スコア計算タイプ
 * 未登録のキャラクターは攻撃力基準（DEFAULT_SCORE_TYPE）を使う。
 * 新キャラクターはここに追記するだけでよい。
 */
const DEFAULT_SCORE_TYPE: ScoreType = "atk";

const SCORE_TYPE_BY_NAME: Record<string, ScoreType> = {
  // HP参照キャラクター
  胡桃: "hp",
  鍾離: "hp",
  珊瑚宮心海: "hp",
  夜蘭: "hp",
  ニィロウ: "hp",
  ディシア: "hp",
  白朮: "hp",
  フリーナ: "hp",
  ヌヴィレット: "hp",
  シグウィン: "hp",
  ムアラニ: "hp",
  // 防御力参照キャラクター
  ノエル: "def",
  荒瀧一斗: "def",
  ゴロー: "def",
  雲菫: "def",
  千織: "def",
  シロネン: "def",
  カチーナ: "def",
  // 元素熟知特化キャラクター
  楓原万葉: "em",
  スクロース: "em",
  ナヒーダ: "em",
  綺良々: "em",
  ヨォーヨ: "em",
  コレイ: "em",
  ティナリ: "em",
  久岐忍: "em",
  ラウマ: "em",
  アイノ: "em",
};

/** キャラクターの推奨スコア計算タイプを返す（マスターデータの scoreType を優先） */
export function getScoreType(
  character: { name: string; scoreType?: string | null },
): ScoreType {
  const fromDb = character.scoreType as ScoreType | undefined;
  if (fromDb && fromDb in SCORE_TYPE_LABEL) return fromDb;
  return SCORE_TYPE_BY_NAME[character.name] ?? DEFAULT_SCORE_TYPE;
}

/**
 * APIの specialProp からスコア計算タイプを推定する（同期時に使用）。
 * 名前ベースの上書き（胡桃=hp など）もここで適用する。
 */
export function inferScoreType(
  specialProp: string | null | undefined,
  name: string,
): ScoreType {
  if (SCORE_TYPE_BY_NAME[name]) return SCORE_TYPE_BY_NAME[name];

  switch (specialProp) {
    case "FIGHT_PROP_HP_PERCENT":
      return "hp";
    case "FIGHT_PROP_DEFENSE_PERCENT":
      return "def";
    case "FIGHT_PROP_ELEMENT_MASTERY":
      return "em";
    case "FIGHT_PROP_ATTACK_PERCENT":
      return "atk";
    default:
      return DEFAULT_SCORE_TYPE;
  }
}

/** 1部位分のスコアを計算する */
export function calcPieceScore(
  piece: ArtifactPiece,
  type: ScoreType = DEFAULT_SCORE_TYPE,
): number {
  let score = 0;
  for (const sub of piece.substats) {
    if (sub.stat === "会心率") score += sub.value * 2;
    else if (sub.stat === "会心ダメージ") score += sub.value;
    else score += SCORE_FORMULAS[type](sub);
  }
  return Math.round(score * 10) / 10;
}

/** 5部位合計のスコアを計算する */
export function calcTotalScore(
  artifacts: ArtifactState,
  type: ScoreType = DEFAULT_SCORE_TYPE,
): number {
  const total = Object.values(artifacts).reduce(
    (sum, piece) => sum + calcPieceScore(piece, type),
    0,
  );
  return Math.round(total * 10) / 10;
}
