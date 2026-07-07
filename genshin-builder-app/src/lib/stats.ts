/**
 * キャラクターステータス自動計算エンジン
 *
 * 以下を合算して現在のステータスを計算する。
 *   1. キャラクター基礎ステータス（レベル・突破段階）
 *   2. 武器ステータス（レベル別の基礎攻撃力・サブステータス）
 *   3. 聖遺物メインステータス（★5のレベル別数値を線形補間）
 *   4. 聖遺物サブステータス（ユーザー入力値）
 *   5. セット効果（2セット効果の常時ステータス補正のみ。条件付き効果は対象外）
 *
 * すべて純粋関数のため、クライアント側で入力変更のたびに再計算できる。
 */

import type { AvatarStats, WeaponLevelStat } from "@/lib/api/amber-details";
import type { ArtifactState, Element } from "@/types/character";

/** 表示するステータスのキー */
export type StatKey =
  | "hp"
  | "atk"
  | "def"
  | "em"
  | "critRate"
  | "critDmg"
  | "er"
  | "healing"
  | "incomingHealing"
  | "shield"
  | "elemDmg"
  | "physDmg";

export const STAT_LABELS: Record<StatKey, string> = {
  hp: "HP",
  atk: "攻撃力",
  def: "防御力",
  em: "元素熟知",
  critRate: "会心率",
  critDmg: "会心ダメージ",
  er: "元素チャージ効率",
  healing: "与える治療効果",
  incomingHealing: "受ける治療効果",
  shield: "シールド強化",
  elemDmg: "元素ダメージバフ",
  physDmg: "物理ダメージバフ",
};

/** %表記するステータス */
export const PERCENT_STATS = new Set<StatKey>([
  "critRate",
  "critDmg",
  "er",
  "healing",
  "incomingHealing",
  "shield",
  "elemDmg",
  "physDmg",
]);

export type StatValues = Record<StatKey, number>;

/** 集計用の内部バケット */
interface StatBucket {
  hpPct: number;
  hpFlat: number;
  atkPct: number;
  atkFlat: number;
  defPct: number;
  defFlat: number;
  em: number;
  critRate: number;
  critDmg: number;
  er: number;
  healing: number;
  incomingHealing: number;
  shield: number;
  elemDmg: Partial<Record<Element, number>>;
  physDmg: number;
}

function emptyBucket(): StatBucket {
  return {
    hpPct: 0,
    hpFlat: 0,
    atkPct: 0,
    atkFlat: 0,
    defPct: 0,
    defFlat: 0,
    em: 0,
    critRate: 0,
    critDmg: 0,
    er: 0,
    healing: 0,
    incomingHealing: 0,
    shield: 0,
    elemDmg: {},
    physDmg: 0,
  };
}

// ---------------------------------------------------------
// 1. キャラクター基礎ステータス
// ---------------------------------------------------------

/** レベルと突破段階からキャラクターの基礎HP/攻撃/防御と突破ボーナスを計算する */
function applyCharacterBase(
  stats: AvatarStats,
  level: number,
  ascension: number,
  bucket: StatBucket,
): { baseHp: number; baseAtk: number; baseDef: number } {
  const promote =
    [...stats.promotes]
      .sort((a, b) => a.promoteLevel - b.promoteLevel)
      .find((p) => p.promoteLevel === Math.min(ascension, 6)) ?? null;

  const base = { baseHp: 0, baseAtk: 0, baseDef: 0 };

  for (const prop of stats.props) {
    const value =
      prop.initValue * (prop.curveValues[Math.min(level, 90) - 1] ?? 1) +
      (promote?.addProps[prop.propType] ?? 0);
    if (prop.propType === "FIGHT_PROP_BASE_HP") base.baseHp = value;
    if (prop.propType === "FIGHT_PROP_BASE_ATTACK") base.baseAtk = value;
    if (prop.propType === "FIGHT_PROP_BASE_DEFENSE") base.baseDef = value;
  }

  // 突破ボーナス（会心ダメージ+38.4% など。%系は小数で入っているので×100）
  if (promote) {
    for (const [propType, value] of Object.entries(promote.addProps)) {
      applyFightProp(propType, value, bucket, true);
    }
  }
  return base;
}

/**
 * FIGHT_PROP_* をバケットへ加算する。
 * fraction=true のとき%系の値は小数（0.384=38.4%）として扱う。
 */
function applyFightProp(
  propType: string,
  value: number,
  bucket: StatBucket,
  fraction: boolean,
): void {
  const pct = fraction ? value * 100 : value;
  switch (propType) {
    case "FIGHT_PROP_HP_PERCENT":
      bucket.hpPct += pct;
      break;
    case "FIGHT_PROP_ATTACK_PERCENT":
      bucket.atkPct += pct;
      break;
    case "FIGHT_PROP_DEFENSE_PERCENT":
      bucket.defPct += pct;
      break;
    case "FIGHT_PROP_ELEMENT_MASTERY":
      bucket.em += value;
      break;
    case "FIGHT_PROP_CRITICAL":
      bucket.critRate += pct;
      break;
    case "FIGHT_PROP_CRITICAL_HURT":
      bucket.critDmg += pct;
      break;
    case "FIGHT_PROP_CHARGE_EFFICIENCY":
      bucket.er += pct;
      break;
    case "FIGHT_PROP_HEAL_ADD":
      bucket.healing += pct;
      break;
    case "FIGHT_PROP_HEALED_ADD":
      bucket.incomingHealing += pct;
      break;
    case "FIGHT_PROP_PHYSICAL_ADD_HURT":
      bucket.physDmg += pct;
      break;
    case "FIGHT_PROP_FIRE_ADD_HURT":
      bucket.elemDmg.pyro = (bucket.elemDmg.pyro ?? 0) + pct;
      break;
    case "FIGHT_PROP_WATER_ADD_HURT":
      bucket.elemDmg.hydro = (bucket.elemDmg.hydro ?? 0) + pct;
      break;
    case "FIGHT_PROP_ELEC_ADD_HURT":
      bucket.elemDmg.electro = (bucket.elemDmg.electro ?? 0) + pct;
      break;
    case "FIGHT_PROP_ICE_ADD_HURT":
      bucket.elemDmg.cryo = (bucket.elemDmg.cryo ?? 0) + pct;
      break;
    case "FIGHT_PROP_WIND_ADD_HURT":
      bucket.elemDmg.anemo = (bucket.elemDmg.anemo ?? 0) + pct;
      break;
    case "FIGHT_PROP_ROCK_ADD_HURT":
      bucket.elemDmg.geo = (bucket.elemDmg.geo ?? 0) + pct;
      break;
    case "FIGHT_PROP_GRASS_ADD_HURT":
      bucket.elemDmg.dendro = (bucket.elemDmg.dendro ?? 0) + pct;
      break;
  }
}

// ---------------------------------------------------------
// 3. 聖遺物メインステータス（★5・レベル別数値の線形補間）
// ---------------------------------------------------------

/** ★5聖遺物メインステータスの Lv.0 → Lv.20 の数値（実ゲームの値はほぼ線形） */
const MAIN_STAT_RANGE: Record<string, { base: number; max: number }> = {
  HP: { base: 717, max: 4780 },
  攻撃力: { base: 47, max: 311 },
  "HP%": { base: 7.0, max: 46.6 },
  "攻撃力%": { base: 7.0, max: 46.6 },
  "防御力%": { base: 8.7, max: 58.3 },
  元素熟知: { base: 28, max: 186.5 },
  元素チャージ効率: { base: 7.8, max: 51.8 },
  会心率: { base: 4.7, max: 31.1 },
  会心ダメージ: { base: 9.3, max: 62.2 },
  与える治療効果: { base: 5.4, max: 35.9 },
  物理ダメージ: { base: 10.9, max: 58.3 },
  炎元素ダメージ: { base: 8.7, max: 46.6 },
  水元素ダメージ: { base: 8.7, max: 46.6 },
  雷元素ダメージ: { base: 8.7, max: 46.6 },
  氷元素ダメージ: { base: 8.7, max: 46.6 },
  風元素ダメージ: { base: 8.7, max: 46.6 },
  岩元素ダメージ: { base: 8.7, max: 46.6 },
  草元素ダメージ: { base: 8.7, max: 46.6 },
};

/** メインステータスの数値をレベルから求める */
export function mainStatValue(statName: string, level: number): number {
  const range = MAIN_STAT_RANGE[statName];
  if (!range) return 0;
  const t = Math.min(Math.max(level, 0), 20) / 20;
  const value = range.base + (range.max - range.base) * t;
  return Math.round(value * 10) / 10;
}

/** ステータス名（日本語）をバケットへ加算する */
function applyNamedStat(stat: string, value: number, bucket: StatBucket): void {
  switch (stat) {
    case "HP":
      bucket.hpFlat += value;
      break;
    case "HP%":
      bucket.hpPct += value;
      break;
    case "攻撃力":
      bucket.atkFlat += value;
      break;
    case "攻撃力%":
      bucket.atkPct += value;
      break;
    case "防御力":
      bucket.defFlat += value;
      break;
    case "防御力%":
      bucket.defPct += value;
      break;
    case "元素熟知":
      bucket.em += value;
      break;
    case "会心率":
      bucket.critRate += value;
      break;
    case "会心ダメージ":
      bucket.critDmg += value;
      break;
    case "元素チャージ効率":
      bucket.er += value;
      break;
    case "与える治療効果":
      bucket.healing += value;
      break;
    case "物理ダメージ":
      bucket.physDmg += value;
      break;
    default: {
      // "○元素ダメージ"
      const match = stat.match(/^(炎|水|雷|氷|風|岩|草)元素ダメージ$/);
      if (match) {
        const element = {
          炎: "pyro",
          水: "hydro",
          雷: "electro",
          氷: "cryo",
          風: "anemo",
          岩: "geo",
          草: "dendro",
        }[match[1]] as Element;
        bucket.elemDmg[element] = (bucket.elemDmg[element] ?? 0) + value;
      }
    }
  }
}

// ---------------------------------------------------------
// 5. セット効果（2セット効果の常時補正をテキストから抽出）
// ---------------------------------------------------------

const SET_EFFECT_PATTERN =
  /(シールド強化|与える治療効果|元素チャージ効率|元素熟知|会心率|会心ダメージ|攻撃力|防御力|HP|物理ダメージ|(?:炎|水|雷|氷|風|岩|草)元素ダメージ)\+([\d.]+)(%?)/g;

/**
 * セット効果の説明文から常時有効なステータス補正を抽出して加算する。
 * （「〜の場合」等の条件付き効果も文面上は拾われるが、2セット効果は
 * ほぼ無条件の補正のみなので実用上問題ない）
 */
function applySetEffectText(text: string, bucket: StatBucket): void {
  for (const match of text.matchAll(SET_EFFECT_PATTERN)) {
    const [, statName, valueStr, percent] = match;
    const value = Number(valueStr);
    if (!Number.isFinite(value)) continue;

    if (statName === "シールド強化") {
      bucket.shield += value;
    } else if (["HP", "攻撃力", "防御力"].includes(statName)) {
      // セット効果のHP/攻撃力/防御力は%表記のみ採用（実数加算のセットは存在しない）
      if (percent === "%") applyNamedStat(`${statName}%`, value, bucket);
    } else {
      applyNamedStat(statName, value, bucket);
    }
  }
}

// ---------------------------------------------------------
// メイン計算
// ---------------------------------------------------------

export interface ComputeStatsInput {
  /** キャラクターのステータス計算用データ */
  avatarStats: AvatarStats;
  /** キャラクターの元素（元素ダメージバフ表示用） */
  element: Element;
  level: number;
  ascension: number;
  /** 装備武器のレベル別ステータス（未装備は null） */
  weaponLevelStat: WeaponLevelStat | null;
  /** 武器サブステータスの FIGHT_PROP_*（無い場合は null） */
  weaponSubStatProp: string | null;
  artifacts: ArtifactState;
  /** 装備中セットの2セット効果テキスト（2つ以上装備しているセットのみ） */
  activeSetEffects: string[];
}

/** 現在のステータスを計算する */
export function computeStats(input: ComputeStatsInput): StatValues {
  const bucket = emptyBucket();

  // 1. キャラクター基礎（レベル・突破）
  const base = applyCharacterBase(
    input.avatarStats,
    input.level,
    input.ascension,
    bucket,
  );

  // 2. 武器（基礎攻撃力 + サブステータス）
  const weaponBaseAtk = input.weaponLevelStat?.baseAttack ?? 0;
  if (input.weaponSubStatProp && input.weaponLevelStat?.subStatValue != null) {
    applyFightProp(
      input.weaponSubStatProp,
      input.weaponLevelStat.subStatValue,
      bucket,
      true,
    );
  }

  // 3-4. 聖遺物（メインステータス + サブステータス）
  for (const piece of Object.values(input.artifacts)) {
    if (piece.mainStat) {
      applyNamedStat(piece.mainStat, mainStatValue(piece.mainStat, piece.level), bucket);
    }
    for (const sub of piece.substats) {
      // %系サブステの名前はメインと同じ表記（"攻撃力%"等）なのでそのまま加算できる
      applyNamedStat(sub.stat, sub.value, bucket);
    }
  }

  // 5. セット効果
  for (const text of input.activeSetEffects) {
    applySetEffectText(text, bucket);
  }

  const round = (n: number) => Math.round(n * 10) / 10;

  return {
    hp: Math.round(base.baseHp * (1 + bucket.hpPct / 100) + bucket.hpFlat),
    atk: Math.round(
      (base.baseAtk + weaponBaseAtk) * (1 + bucket.atkPct / 100) +
        bucket.atkFlat,
    ),
    def: Math.round(base.baseDef * (1 + bucket.defPct / 100) + bucket.defFlat),
    em: Math.round(bucket.em),
    critRate: round(5 + bucket.critRate),
    critDmg: round(50 + bucket.critDmg),
    er: round(100 + bucket.er),
    healing: round(bucket.healing),
    incomingHealing: round(bucket.incomingHealing),
    shield: round(bucket.shield),
    elemDmg: round(bucket.elemDmg[input.element] ?? 0),
    physDmg: round(bucket.physDmg),
  };
}
