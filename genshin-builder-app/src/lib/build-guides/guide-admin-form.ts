/**
 * 構造化育成情報管理フォーム用の表示名・ステータス・構成ヘルパー。
 * 保存値は既存 API 識別子と互換を維持する。
 */

export const ADMIN_WORKING_DRAFT_KEY = "adminWorkingDraft";

export type ArtifactCompositionMode = "four" | "two_two" | "two" | "undetermined";

export type ArtifactSetMaster = {
  setId: string;
  name: string;
  iconUrl: string;
  rarity: number | null;
  twoPieceEffect: string;
  fourPieceEffect: string;
  isAvailable: boolean;
};

export type TargetValueType = "minimum" | "maximum" | "range" | "target" | "ratio";

export type TargetDraft = {
  id: string;
  stat: string;
  valueType: TargetValueType;
  minimum: string;
  maximum: string;
  target: string;
  unit: "flat" | "percent" | "";
  condition: string;
  citationId: string;
  leftStat: string;
  leftValue: string;
  rightStat: string;
  rightValue: string;
};

export const RECOMMENDATION_LEVEL_LABELS: Record<string, string> = {
  strongly_recommended: "強く推奨",
  recommended: "推奨",
  situational: "状況次第",
  alternative: "代替",
};

export const DATA_ORIGIN_LABELS: Record<string, string> = {
  manual: "手動入力",
  evidence_mention: "動画内で言及",
  legacy_preference: "旧形式から移行",
  imported: "インポート",
  merged: "統合結果",
  structured: "構造化データ",
};

export const REVIEW_STATUS_LABELS: Record<string, string> = {
  draft: "下書き",
  review_required: "要確認",
  admin_confirmed: "管理者確認済み",
};

export const STATUS_LABELS: Record<string, string> = {
  pending_review: "レビュー待ち",
  approved: "承認済み",
  rejected: "却下",
  published: "公開中",
};

export const UNIT_LABELS: Record<string, string> = {
  percent: "%",
  flat: "固定値",
};

export const VALUE_TYPE_LABELS: Record<TargetValueType, string> = {
  minimum: "以上（minimum）",
  maximum: "以下（maximum）",
  range: "範囲（range）",
  target: "目標値（target）",
  ratio: "比率（ratio）",
};

/** 目標ステータス用（stat ID + 既定単位） */
export const TARGET_STAT_OPTIONS: Array<{
  id: string;
  label: string;
  defaultUnit: "flat" | "percent";
}> = [
  { id: "hp", label: "HP", defaultUnit: "flat" },
  { id: "hp", label: "HP%", defaultUnit: "percent" },
  { id: "atk", label: "攻撃力", defaultUnit: "flat" },
  { id: "atk", label: "攻撃力%", defaultUnit: "percent" },
  { id: "def", label: "防御力", defaultUnit: "flat" },
  { id: "def", label: "防御力%", defaultUnit: "percent" },
  { id: "em", label: "元素熟知", defaultUnit: "flat" },
  { id: "er", label: "元素チャージ効率", defaultUnit: "percent" },
  { id: "critRate", label: "会心率", defaultUnit: "percent" },
  { id: "critDmg", label: "会心ダメージ", defaultUnit: "percent" },
  { id: "healing", label: "与える治療効果", defaultUnit: "percent" },
  { id: "elemDmg", label: "元素ダメージ", defaultUnit: "percent" },
  { id: "physDmg", label: "物理ダメージ", defaultUnit: "percent" },
];

export const MAIN_STAT_OPTIONS_BY_SLOT: Record<
  "sands" | "goblet" | "circlet",
  string[]
> = {
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
    "会心率",
    "会心ダメージ",
    "与える治療効果",
    "元素熟知",
  ],
};

export const SLOT_LABELS: Record<string, string> = {
  sands: "時計",
  goblet: "杯",
  circlet: "冠",
};

export function labelOf(
  map: Record<string, string>,
  value: string | null | undefined,
  fallback?: string,
): string {
  if (!value) return fallback ?? "未設定";
  return map[value] ?? fallback ?? value;
}

export function defaultUnitForStat(stat: string): "flat" | "percent" {
  if (stat === "em" || stat === "hp" || stat === "atk" || stat === "def") {
    return "flat";
  }
  return "percent";
}

export function unitWarnForStat(
  stat: string,
  unit: "flat" | "percent" | "",
): string | null {
  if (!unit || !stat) return null;
  if (["critRate", "critDmg", "er", "healing", "elemDmg", "physDmg"].includes(stat) && unit === "flat") {
    return `${stat} に固定値は通常使いません`;
  }
  if (stat === "em" && unit === "percent") {
    return "元素熟知に % は通常使いません";
  }
  return null;
}

export function emptyTarget(id: string): TargetDraft {
  return {
    id,
    stat: "er",
    valueType: "minimum",
    minimum: "",
    maximum: "",
    target: "",
    unit: "percent",
    condition: "",
    citationId: "",
    leftStat: "critRate",
    leftValue: "1",
    rightStat: "critDmg",
    rightValue: "2",
  };
}

export function parseOptionalNumber(raw: string): number | null | undefined {
  const t = raw.trim();
  if (t === "") return undefined;
  const n = Number(t);
  if (!Number.isFinite(n)) return null;
  return n;
}

/** 値形式に応じて API 向け recommendedStats / targets 行を生成 */
export function targetDraftToPayload(row: TargetDraft): {
  recommended: Record<string, unknown> | null;
  target: Record<string, unknown> | null;
  warnings: string[];
} {
  const warnings: string[] = [];
  if (!row.stat) {
    warnings.push("ステータス未選択");
    return { recommended: null, target: null, warnings };
  }
  const unitWarn = unitWarnForStat(row.stat, row.unit);
  if (unitWarn) warnings.push(unitWarn);

  if (row.valueType === "ratio") {
    const leftValue = parseOptionalNumber(row.leftValue);
    const rightValue = parseOptionalNumber(row.rightValue);
    if (leftValue == null || rightValue == null || leftValue <= 0 || rightValue <= 0) {
      warnings.push("比率の左右の値が不正です");
      return { recommended: null, target: null, warnings };
    }
    return {
      recommended: {
        stat: row.stat,
        valueType: "ratio",
        leftStat: row.leftStat,
        leftValue,
        rightStat: row.rightStat,
        rightValue,
        unit: row.unit || null,
        condition: row.condition || null,
        citationId: row.citationId || null,
      },
      // モバイル互換 targets には比率を載せない
      target: null,
      warnings,
    };
  }

  const minimum = parseOptionalNumber(row.minimum);
  const maximum = parseOptionalNumber(row.maximum);
  const recommended = parseOptionalNumber(row.target);
  if (minimum === null || maximum === null || recommended === null) {
    warnings.push("数値が不正です（NaN / Infinity）");
    return { recommended: null, target: null, warnings };
  }
  if (
    row.valueType === "range" &&
    minimum != null &&
    maximum != null &&
    minimum > maximum
  ) {
    warnings.push("minimum が maximum を超えています");
  }
  if (minimum != null && minimum < 0) warnings.push("負数があります");
  if (maximum != null && maximum < 0) warnings.push("負数があります");
  if (recommended != null && recommended < 0) warnings.push("負数があります");

  const out: Record<string, unknown> = {
    stat: row.stat,
    valueType: row.valueType,
    unit: row.unit || null,
    condition: row.condition || null,
    citationId: row.citationId || null,
  };
  const target: Record<string, unknown> = { stat: row.stat };
  if (row.unit) target.unit = row.unit;

  if (row.valueType === "minimum") {
    if (minimum === undefined) warnings.push("minimum が未入力です");
    else {
      out.minimum = minimum;
      target.min = minimum;
    }
  } else if (row.valueType === "maximum") {
    if (maximum === undefined) warnings.push("maximum が未入力です");
    else {
      out.maximum = maximum;
      target.max = maximum;
    }
  } else if (row.valueType === "range") {
    if (minimum === undefined || maximum === undefined) {
      warnings.push("range には minimum と maximum が必要です");
    } else {
      out.minimum = minimum;
      out.maximum = maximum;
      target.min = minimum;
      target.max = maximum;
    }
  } else if (row.valueType === "target") {
    if (recommended === undefined) warnings.push("目標値が未入力です");
    else {
      out.recommended = recommended;
      target.recommended = recommended;
    }
  }

  return { recommended: out, target, warnings };
}

export function payloadToTargetDrafts(raw: unknown): TargetDraft[] {
  const list = Array.isArray(raw) ? raw : [];
  if (list.length === 0) return [];
  return list.map((item, index) => {
    const map =
      item && typeof item === "object" && !Array.isArray(item)
        ? (item as Record<string, unknown>)
        : {};
    const valueTypeRaw = String(map.valueType ?? "");
    let valueType: TargetValueType = "target";
    if (
      valueTypeRaw === "minimum" ||
      valueTypeRaw === "maximum" ||
      valueTypeRaw === "range" ||
      valueTypeRaw === "target" ||
      valueTypeRaw === "ratio"
    ) {
      valueType = valueTypeRaw;
    } else if (map.min != null && map.max != null) valueType = "range";
    else if (map.min != null || map.minimum != null) valueType = "minimum";
    else if (map.max != null || map.maximum != null) valueType = "maximum";

    const min = map.minimum ?? map.min;
    const max = map.maximum ?? map.max;
    const rec = map.recommended ?? map.target;
    return {
      id: `t-${index}-${Date.now()}`,
      stat: typeof map.stat === "string" ? map.stat : "er",
      valueType,
      minimum: min == null ? "" : String(min),
      maximum: max == null ? "" : String(max),
      target: rec == null ? "" : String(rec),
      unit: map.unit === "flat" || map.unit === "percent" ? map.unit : "",
      condition: typeof map.condition === "string" ? map.condition : "",
      citationId: typeof map.citationId === "string" ? map.citationId : "",
      leftStat: typeof map.leftStat === "string" ? map.leftStat : "critRate",
      leftValue: map.leftValue == null ? "1" : String(map.leftValue),
      rightStat: typeof map.rightStat === "string" ? map.rightStat : "critDmg",
      rightValue: map.rightValue == null ? "2" : String(map.rightValue),
    };
  });
}

export function inferCompositionMode(sets: Array<{ setId: string; pieces: number | null }>): ArtifactCompositionMode {
  if (sets.length === 0) return "undetermined";
  if (sets.some((s) => s.pieces == null)) return "undetermined";
  if (sets.length === 1 && sets[0]?.pieces === 4) return "four";
  if (sets.length === 1 && sets[0]?.pieces === 2) return "two";
  if (sets.length === 2 && sets[0]?.pieces === 2 && sets[1]?.pieces === 2) {
    return "two_two";
  }
  return "undetermined";
}

export function formatArtifactCompositionPreview(
  mode: ArtifactCompositionMode,
  setAId: string,
  setBId: string,
  nameOf: (id: string) => string,
): string {
  if (mode === "undetermined") {
    return setAId
      ? `${nameOf(setAId)}（必要部位数 未確定）`
      : "構成未確定";
  }
  if (mode === "four") {
    return setAId ? `${nameOf(setAId)} ×4` : "セット未選択 ×4";
  }
  if (mode === "two") {
    return setAId ? `${nameOf(setAId)} ×2` : "セット未選択 ×2";
  }
  const a = setAId ? `${nameOf(setAId)} ×2` : "セットA未選択 ×2";
  const b = setBId ? `${nameOf(setBId)} ×2` : "セットB未選択 ×2";
  return `${a}\n${b}`;
}

export function buildArtifactSetsPayload(
  mode: ArtifactCompositionMode,
  setAId: string,
  setBId: string,
): Array<{ setId: string; pieces: number | null }> {
  if (mode === "undetermined") {
    return setAId ? [{ setId: setAId, pieces: null }] : [];
  }
  if (mode === "four") {
    return setAId ? [{ setId: setAId, pieces: 4 }] : [];
  }
  if (mode === "two") {
    return setAId ? [{ setId: setAId, pieces: 2 }] : [];
  }
  const out: Array<{ setId: string; pieces: number | null }> = [];
  if (setAId) out.push({ setId: setAId, pieces: 2 });
  if (setBId) out.push({ setId: setBId, pieces: 2 });
  return out;
}

export function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

export function stripAdminWorkingDraft(
  structured: Record<string, unknown>,
): Record<string, unknown> {
  const next = { ...structured };
  delete next[ADMIN_WORKING_DRAFT_KEY];
  return next;
}

export function readAdminWorkingDraft(structured: Record<string, unknown>): {
  structured?: Record<string, unknown>;
  targets?: unknown;
  mainStats?: unknown;
  priority?: unknown;
  context?: unknown;
  adminNotes?: string;
} | null {
  const draft = asRecord(structured[ADMIN_WORKING_DRAFT_KEY]);
  if (Object.keys(draft).length === 0) return null;
  return {
    structured: asRecord(draft.structured),
    targets: draft.targets,
    mainStats: draft.mainStats,
    priority: draft.priority,
    context: draft.context,
    adminNotes: typeof draft.adminNotes === "string" ? draft.adminNotes : undefined,
  };
}
