import type {
  ArtifactSlotKey,
  Element,
  WeaponType,
} from "@/types/character";

/** 元素ごとの表示名とテーマカラー */
export const ELEMENT_INFO: Record<
  Element,
  { label: string; color: string; bgClass: string; textClass: string }
> = {
  pyro: {
    label: "炎",
    color: "#ff6b4a",
    bgClass: "bg-red-500/15",
    textClass: "text-red-400",
  },
  hydro: {
    label: "水",
    color: "#4fc3f7",
    bgClass: "bg-sky-500/15",
    textClass: "text-sky-400",
  },
  electro: {
    label: "雷",
    color: "#b388ff",
    bgClass: "bg-purple-500/15",
    textClass: "text-purple-400",
  },
  cryo: {
    label: "氷",
    color: "#80deea",
    bgClass: "bg-cyan-500/15",
    textClass: "text-cyan-300",
  },
  anemo: {
    label: "風",
    color: "#69f0ae",
    bgClass: "bg-emerald-500/15",
    textClass: "text-emerald-400",
  },
  geo: {
    label: "岩",
    color: "#ffd54f",
    bgClass: "bg-amber-500/15",
    textClass: "text-amber-400",
  },
  dendro: {
    label: "草",
    color: "#a5d6a7",
    bgClass: "bg-green-500/15",
    textClass: "text-green-400",
  },
};

/** 武器種の表示名 */
export const WEAPON_TYPE_INFO: Record<WeaponType, { label: string }> = {
  sword: { label: "片手剣" },
  claymore: { label: "両手剣" },
  polearm: { label: "長柄武器" },
  bow: { label: "弓" },
  catalyst: { label: "法器" },
};

/** フィルターUI用の選択肢 */
export const ELEMENT_OPTIONS = Object.entries(ELEMENT_INFO).map(
  ([value, info]) => ({ value: value as Element, label: info.label }),
);

export const WEAPON_TYPE_OPTIONS = Object.entries(WEAPON_TYPE_INFO).map(
  ([value, info]) => ({ value: value as WeaponType, label: info.label }),
);

// ============================================================
// 聖遺物関連
// ============================================================

/** 聖遺物の部位名 */
export const ARTIFACT_SLOT_INFO: Record<ArtifactSlotKey, { label: string }> = {
  flower: { label: "花" },
  plume: { label: "羽" },
  sands: { label: "時計" },
  goblet: { label: "杯" },
  circlet: { label: "冠" },
};

export const ARTIFACT_SLOT_KEYS = Object.keys(
  ARTIFACT_SLOT_INFO,
) as ArtifactSlotKey[];

/** 部位ごとのメインステータス選択肢 */
export const MAIN_STAT_OPTIONS: Record<ArtifactSlotKey, string[]> = {
  flower: ["HP"],
  plume: ["攻撃力"],
  sands: ["HP%", "攻撃力%", "防御力%", "元素熟知", "元素チャージ効率"],
  goblet: [
    "HP%",
    "攻撃力%",
    "防御力%",
    "元素熟知",
    "炎元素ダメージ",
    "水元素ダメージ",
    "雷元素ダメージ",
    "氷元素ダメージ",
    "風元素ダメージ",
    "岩元素ダメージ",
    "草元素ダメージ",
    "物理ダメージ",
  ],
  circlet: [
    "HP%",
    "攻撃力%",
    "防御力%",
    "元素熟知",
    "会心率",
    "会心ダメージ",
    "与える治療効果",
  ],
};

/** サブステータスの選択肢 */
export const SUB_STAT_OPTIONS = [
  "会心率",
  "会心ダメージ",
  "攻撃力%",
  "攻撃力",
  "HP%",
  "HP",
  "防御力%",
  "防御力",
  "元素熟知",
  "元素チャージ効率",
] as const;
