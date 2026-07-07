/**
 * Project Amber（gi.yatta.moe）の詳細データ取得
 *
 * キャラクター詳細画面で使う「スキル・凸効果・武器性能・聖遺物セット効果」は
 * 量が多くマスターDBには保存せず、表示時にサーバー側で取得して
 * Next.js のキャッシュ（24時間）を効かせる方針。
 * APIが落ちても null を返し、画面側は基本情報のみで動作を継続する。
 */

import { WEAPON_LEVEL_OPTIONS } from "@/lib/input-limits";

export { WEAPON_LEVEL_OPTIONS };

const BASE_URL = "https://gi.yatta.moe";
const ASSET_URL = `${BASE_URL}/assets/UI`;
const REVALIDATE_SEC = 60 * 60 * 24;

// ---------------------------------------------------------
// 正規化済みの型（画面側はこの型だけを扱う）
// ---------------------------------------------------------

export type TalentKind = "normal" | "skill" | "burst" | "passive";

export interface TalentInfo {
  kind: TalentKind;
  name: string;
  description: string;
  iconUrl: string | null;
}

export interface ConstellationInfo {
  /** 凸数 (1-6) */
  position: number;
  name: string;
  description: string;
}

/** 基礎ステータス1項目分（レベル1の初期値 + レベル別成長倍率） */
export interface StatCurveProp {
  /** FIGHT_PROP_BASE_HP など */
  propType: string;
  initValue: number;
  /** index = レベル-1 (Lv.1〜90) の成長倍率 */
  curveValues: number[];
}

/** 突破1段階分のステータス加算 */
export interface StatPromote {
  promoteLevel: number;
  unlockMaxLevel: number;
  /** FIGHT_PROP_* → 加算値（%系は小数。例: 0.384 = 38.4%） */
  addProps: Record<string, number>;
}

/** キャラクターのステータス計算用データ */
export interface AvatarStats {
  props: StatCurveProp[];
  promotes: StatPromote[];
}

export interface AvatarDetail {
  talents: TalentInfo[];
  constellations: ConstellationInfo[];
  /** ステータス自動計算用データ（取得失敗時は null） */
  stats: AvatarStats | null;
}

/** 武器レベル（10刻み）ごとの実ステータス */
export interface WeaponLevelStat {
  level: number;
  baseAttack: number;
  /** サブステータス値（%系は小数。元素熟知は実数。無い場合は null） */
  subStatValue: number | null;
}

export interface WeaponDetail {
  id: string;
  name: string;
  rarity: number;
  weaponTypeLabel: string;
  iconUrl: string;
  /** 基礎攻撃力（Lv.1時点の初期値） */
  baseAttack: number;
  /** サブステータスのFIGHT_PROP_*（無い場合は null） */
  subStatProp: string | null;
  /** サブステータス名（例: "会心ダメージ"。無い場合は null） */
  subStatName: string | null;
  /** サブステータスの初期値表示（例: "14.4%"） */
  subStatValue: string | null;
  /** 武器効果名 */
  effectName: string | null;
  /** 精錬ランク1〜5ごとの効果説明文 */
  effectDescriptions: string[];
  /** レベル（10刻み）ごとの実ステータス */
  levelStats: WeaponLevelStat[];
}

export interface ArtifactSetInfo {
  id: string;
  name: string;
  iconUrl: string;
  /** セット効果（1件なら1セット効果、2件なら2セット/4セット効果） */
  effects: string[];
}

// ---------------------------------------------------------
// APIレスポンスの型（必要な項目のみ）
// ---------------------------------------------------------

interface AmberResponse<T> {
  response: number;
  data: T;
}

interface ApiTalent {
  type: number;
  name: string;
  description: string;
  icon: string | null;
}

interface ApiConstellation {
  name: string;
  description: string;
}

interface ApiUpgrade {
  prop: Array<{ propType: string; initValue: number; type: string }>;
  promote: Array<{
    promoteLevel?: number;
    unlockMaxLevel?: number;
    addProps?: Record<string, number>;
  }>;
}

interface ApiAvatarDetail {
  talent: Record<string, ApiTalent>;
  constellation: Record<string, ApiConstellation>;
  upgrade: ApiUpgrade;
}

interface ApiWeaponDetail {
  id: number;
  rank: number;
  type: string;
  name: string;
  icon: string;
  affix: Record<string, { name: string; upgrade: Record<string, string> }> | null;
  upgrade: ApiUpgrade;
}

/** 成長曲線: レベル → 曲線名 → 倍率 */
type ApiCurveData = Record<string, { curveInfos: Record<string, number> }>;

interface ApiArtifactSet {
  id: number;
  name: string;
  icon: string;
  affixList: Record<string, string> | null;
}

// ---------------------------------------------------------
// 共通ヘルパー
// ---------------------------------------------------------

async function fetchData<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      next: { revalidate: REVALIDATE_SEC },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as AmberResponse<T>;
    return json.data;
  } catch (error) {
    console.error(`詳細データの取得に失敗しました: ${path}`, error);
    return null;
  }
}

/** APIの説明文に含まれる <color=...> タグ等を除去して平文にする */
export function stripMarkup(text: string): string {
  return text
    .replace(/<color=[^>]*>/g, "")
    .replace(/<\/color>/g, "")
    .replace(/<i>|<\/i>/g, "")
    .replace(/\\n/g, "\n");
}

/** ステータス種別 → 日本語名 */
const PROP_LABEL: Record<string, string> = {
  FIGHT_PROP_BASE_ATTACK: "基礎攻撃力",
  FIGHT_PROP_ATTACK_PERCENT: "攻撃力",
  FIGHT_PROP_CRITICAL: "会心率",
  FIGHT_PROP_CRITICAL_HURT: "会心ダメージ",
  FIGHT_PROP_ELEMENT_MASTERY: "元素熟知",
  FIGHT_PROP_CHARGE_EFFICIENCY: "元素チャージ効率",
  FIGHT_PROP_HP_PERCENT: "HP",
  FIGHT_PROP_DEFENSE_PERCENT: "防御力",
  FIGHT_PROP_PHYSICAL_ADD_HURT: "物理ダメージ",
};

/** %系ステータスかどうか（元素熟知だけ実数） */
function isPercentProp(propType: string): boolean {
  return propType !== "FIGHT_PROP_ELEMENT_MASTERY";
}

const WEAPON_TYPE_LABEL: Record<string, string> = {
  WEAPON_SWORD_ONE_HAND: "片手剣",
  WEAPON_CLAYMORE: "両手剣",
  WEAPON_POLE: "長柄武器",
  WEAPON_BOW: "弓",
  WEAPON_CATALYST: "法器",
};

// ---------------------------------------------------------
// 成長曲線
// ---------------------------------------------------------

const MAX_LEVEL = 90;

/** 成長曲線データを「曲線名 → Lv.1〜90の倍率配列」に変換する */
function buildCurveArrays(
  data: ApiCurveData | null,
  curveTypes: string[],
): Record<string, number[]> {
  const result: Record<string, number[]> = {};
  if (!data) return result;

  for (const type of curveTypes) {
    const values: number[] = [];
    for (let level = 1; level <= MAX_LEVEL; level++) {
      values.push(data[String(level)]?.curveInfos[type] ?? 1);
    }
    result[type] = values;
  }
  return result;
}

/** upgrade データを正規化してステータス計算用の形にする */
function buildStats(
  upgrade: ApiUpgrade | undefined,
  curveData: ApiCurveData | null,
): AvatarStats | null {
  if (!upgrade?.prop || !curveData) return null;

  const curveTypes = upgrade.prop.map((p) => p.type);
  const curves = buildCurveArrays(curveData, curveTypes);

  return {
    props: upgrade.prop.map((p) => ({
      propType: p.propType,
      initValue: p.initValue,
      curveValues: curves[p.type] ?? [],
    })),
    promotes: (upgrade.promote ?? []).map((p) => ({
      promoteLevel: p.promoteLevel ?? 0,
      unlockMaxLevel: p.unlockMaxLevel ?? MAX_LEVEL,
      addProps: p.addProps ?? {},
    })),
  };
}

// ---------------------------------------------------------
// 取得関数
// ---------------------------------------------------------

/** キャラクターのスキル・天賦・凸効果を取得する */
export async function fetchAvatarDetail(
  characterId: string,
): Promise<AvatarDetail | null> {
  const data = await fetchData<ApiAvatarDetail>(
    `/api/v2/jp/avatar/${characterId}`,
  );
  if (!data) return null;

  // type: 0=通常攻撃(+スキル), 1=元素爆発...ではなく、
  // Amberでは 0=アクティブ(通常/スキル/爆発を出現順に含む), 1=パッシブ(突破天賦), 2=固有天賦
  // 実データでは type=0 が通常攻撃とスキル、type=1 が爆発、type=2 がパッシブ群という
  // 並びのキャラもいるため、「type=0/1 の出現順で 通常→スキル→爆発」とみなし、
  // 残りをパッシブとして扱う。
  const entries = Object.keys(data.talent)
    .sort((a, b) => Number(a) - Number(b))
    .map((key) => data.talent[key]);

  const active = entries.filter((t) => t.type === 0 || t.type === 1);
  const passive = entries.filter((t) => t.type !== 0 && t.type !== 1);

  const activeKinds: TalentKind[] = ["normal", "skill", "burst"];
  const talents: TalentInfo[] = [
    ...active.slice(0, 3).map((t, i) => ({
      kind: activeKinds[i],
      name: t.name,
      description: stripMarkup(t.description),
      iconUrl: t.icon ? `${ASSET_URL}/${t.icon}.png` : null,
    })),
    ...passive.map((t) => ({
      kind: "passive" as const,
      name: t.name,
      description: stripMarkup(t.description),
      iconUrl: t.icon ? `${ASSET_URL}/${t.icon}.png` : null,
    })),
  ];

  const constellations: ConstellationInfo[] = Object.keys(data.constellation)
    .sort((a, b) => Number(a) - Number(b))
    .map((key, index) => ({
      position: index + 1,
      name: data.constellation[key].name,
      description: stripMarkup(data.constellation[key].description),
    }));

  // ステータス計算用データ（基礎値 + 成長曲線 + 突破加算）
  const curveData = await fetchData<ApiCurveData>("/api/v2/static/avatarCurve");
  const stats = buildStats(data.upgrade, curveData);

  return { talents, constellations, stats };
}
function findPromote(
  promotes: StatPromote[],
  level: number,
): StatPromote | null {
  const sorted = [...promotes].sort((a, b) => a.promoteLevel - b.promoteLevel);
  // unlockMaxLevel >= level を満たす最小の突破段階を使う
  return sorted.find((p) => p.unlockMaxLevel >= level) ?? sorted.at(-1) ?? null;
}

/** 武器の詳細性能を取得する */
export async function fetchWeaponDetail(
  weaponId: string,
): Promise<WeaponDetail | null> {
  const data = await fetchData<ApiWeaponDetail>(`/api/v2/jp/weapon/${weaponId}`);
  if (!data) return null;

  const props = data.upgrade?.prop ?? [];
  const baseAtkProp = props.find(
    (p) => p.propType === "FIGHT_PROP_BASE_ATTACK",
  );
  const subProp = props.find((p) => p.propType !== "FIGHT_PROP_BASE_ATTACK");

  // 精錬効果（affix は1件のみ想定。upgrade のキー 0-4 が R1-R5）
  const affix = data.affix ? Object.values(data.affix)[0] : null;
  const effectDescriptions = affix
    ? Object.keys(affix.upgrade)
        .sort((a, b) => Number(a) - Number(b))
        .map((key) => stripMarkup(affix.upgrade[key]))
    : [];

  // レベル（10刻み）ごとの実ステータスを成長曲線から計算する
  const curveData = await fetchData<ApiCurveData>("/api/v2/static/weaponCurve");
  const stats = buildStats(data.upgrade, curveData);
  const levelStats: WeaponLevelStat[] = WEAPON_LEVEL_OPTIONS.map((level) => {
    const atkProp = stats?.props.find(
      (p) => p.propType === "FIGHT_PROP_BASE_ATTACK",
    );
    const sub = stats?.props.find(
      (p) => p.propType !== "FIGHT_PROP_BASE_ATTACK",
    );
    const promote = stats ? findPromote(stats.promotes, level) : null;
    const promoteAtk = promote?.addProps["FIGHT_PROP_BASE_ATTACK"] ?? 0;

    return {
      level,
      baseAttack: Math.round(
        (atkProp?.initValue ?? 0) * (atkProp?.curveValues[level - 1] ?? 1) +
          promoteAtk,
      ),
      subStatValue: sub
        ? sub.initValue * (sub.curveValues[level - 1] ?? 1)
        : null,
    };
  });

  return {
    id: String(data.id),
    name: data.name,
    rarity: data.rank,
    weaponTypeLabel: WEAPON_TYPE_LABEL[data.type] ?? data.type,
    iconUrl: `${ASSET_URL}/${data.icon}.png`,
    baseAttack: Math.round(baseAtkProp?.initValue ?? 0),
    subStatProp: subProp?.propType ?? null,
    subStatName: subProp ? (PROP_LABEL[subProp.propType] ?? null) : null,
    subStatValue: subProp
      ? isPercentProp(subProp.propType)
        ? `${(subProp.initValue * 100).toFixed(1)}%`
        : `${Math.round(subProp.initValue)}`
      : null,
    effectName: affix?.name ?? null,
    effectDescriptions,
    levelStats,
  };
}

/** サブステータス値の表示用フォーマット（%系は小数を%表記へ） */
export function formatSubStatValue(
  propType: string | null,
  value: number | null,
): string {
  if (propType === null || value === null) return "-";
  return isPercentProp(propType)
    ? `${(value * 100).toFixed(1)}%`
    : String(Math.round(value));
}

/** 聖遺物セットの一覧（セット効果付き）を取得する */
export async function fetchArtifactSets(): Promise<ArtifactSetInfo[]> {
  const data = await fetchData<{ items: Record<string, ApiArtifactSet> }>(
    "/api/v2/jp/reliquary",
  );
  if (!data) return [];

  return Object.values(data.items)
    .filter((set) => set.name)
    .map((set) => ({
      id: String(set.id),
      name: set.name,
      iconUrl: `${ASSET_URL}/${set.icon}.png`,
      effects: set.affixList
        ? Object.values(set.affixList).map(stripMarkup)
        : [],
    }));
}
