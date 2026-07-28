/**
 * 公開ビルド推奨レスポンスの正規化。
 * - 別名入力を正式フィールドへ変換
 * - 出典を sources + citationId へ正規化
 * - 無効件は警告してスキップ（全体は破壊しない）
 * - investmentPriority は明示値のみ（信頼度から推定しない）
 */

export const PUBLIC_BUILD_RECOMMENDATION_SCHEMA_VERSION = 1 as const;

export type InvestmentPriority = "high" | "medium" | "low";

export type GuideRecommendationLevel =
  | "strongly_recommended"
  | "recommended"
  | "situational"
  | "alternative";

export type WeaponDataOrigin = "structured" | "legacy_preference";

export type PublicSource = {
  id: string;
  videoId: string;
  title: string;
  channelId?: string | null;
  channelTitle: string;
  publishedAt?: string | null;
  reviewedAt?: string | null;
  gameVersion?: string | null;
  sourceUrl: string;
};

export type PublicWeapon = {
  weaponId?: string | null;
  displayName?: string | null;
  rank?: number | null;
  recommendationLevel?: GuideRecommendationLevel | null;
  reason?: string | null;
  conditions: string[];
  role?: string | null;
  citationId?: string | null;
  dataOrigin: WeaponDataOrigin;
};

export type PublicArtifactSetPart = {
  setId: string;
  pieces: number;
};

export type PublicArtifactRecommendation = {
  sets: PublicArtifactSetPart[];
  rank?: number | null;
  recommendationLevel?: GuideRecommendationLevel | null;
  reason?: string | null;
  conditions: string[];
  role?: string | null;
  isAlternative: boolean;
  citationId?: string | null;
};

export type PublicMainStat = {
  slot: "sands" | "goblet" | "circlet";
  /** 正式: 第一候補 */
  primaryStats: string[];
  /** 正式: 代替 */
  alternativeStats: string[];
  /** モバイル互換: primary + alternative */
  stats: string[];
  condition?: string | null;
  citationId?: string | null;
};

export type PublicRecommendedStat = {
  stat: string;
  valueType: "minimum" | "maximum" | "range" | "target" | "ratio";
  minimum?: number | null;
  maximum?: number | null;
  recommended?: number | null;
  unit?: "flat" | "percent" | null;
  condition?: string | null;
  citationId?: string | null;
  leftStat?: string | null;
  leftValue?: number | null;
  rightStat?: string | null;
  rightValue?: number | null;
};

/** モバイル互換 targets */
export type PublicTarget = {
  stat: string;
  recommended?: number;
  min?: number;
  max?: number;
  unit?: "flat" | "percent";
};

export type NormalizeInput = {
  characterId: string;
  label?: string;
  status?: string;
  origin?: string;
  overallConfidence?: number;
  context?: Record<string, unknown>;
  mainStats?: unknown;
  substatPriority?: unknown;
  targets?: unknown;
  recommendedStats?: unknown;
  weapons?: unknown;
  weaponRecommendations?: unknown;
  artifactRecommendations?: unknown;
  artifactSets?: unknown;
  investmentPriority?: unknown;
  gameVersion?: unknown;
  structured?: unknown;
  caveats?: unknown;
  lastVerifiedAt?: string | null;
  publishedAt?: string | null;
  updatedAt?: string | null;
  sources?: unknown;
  evidence?: unknown;
};

export type NormalizeResult = {
  data: Record<string, unknown>;
  warnings: string[];
};

const PRIORITY_SET = new Set(["high", "medium", "low"]);
const LEVEL_SET = new Set([
  "strongly_recommended",
  "recommended",
  "situational",
  "alternative",
]);
const SLOT_SET = new Set(["sands", "goblet", "circlet"]);
const STAT_KEYS = new Set([
  "hp",
  "atk",
  "def",
  "em",
  "critRate",
  "critDmg",
  "er",
  "healing",
  "elemDmg",
  "physDmg",
]);

/** 表示用・別名 → 正規 stat key（未知はそのまま落とす） */
const STAT_ALIASES: Record<string, string> = {
  crit_rate: "critRate",
  crit_damage: "critDmg",
  elemental_mastery: "em",
  energy_recharge: "er",
  atk_percentage: "atk",
  hp_percentage: "hp",
  def_percentage: "def",
  elemental_damage: "elemDmg",
  pyro_damage_bonus: "elemDmg",
  hydro_damage_bonus: "elemDmg",
  electro_damage_bonus: "elemDmg",
  cryo_damage_bonus: "elemDmg",
  anemo_damage_bonus: "elemDmg",
  geo_damage_bonus: "elemDmg",
  dendro_damage_bonus: "elemDmg",
  physical_damage: "physDmg",
  healing_bonus: "healing",
};

export function parseGameVersionParts(raw: unknown): number[] | null {
  if (typeof raw !== "string") return null;
  let s = raw.trim();
  if (!s) return null;
  s = s.replace(/^[Vv]er\.?\s*/, "").replace(/時点$/, "").trim();
  const m = /^(\d+)(?:\.(\d+))?(?:\.(\d+))?/.exec(s);
  if (!m) return null;
  return [Number(m[1]), Number(m[2] ?? 0), Number(m[3] ?? 0)];
}

export function compareGameVersions(a: unknown, b: unknown): number | null {
  const pa = parseGameVersionParts(a);
  const pb = parseGameVersionParts(b);
  if (!pa || !pb) return null;
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

export function parseInvestmentPriority(raw: unknown): InvestmentPriority | null {
  if (typeof raw !== "string") return null;
  const v = raw.trim().toLowerCase();
  if (v === "高") return "high";
  if (v === "中") return "medium";
  if (v === "低") return "low";
  if (PRIORITY_SET.has(v)) return v as InvestmentPriority;
  return null;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown, max = 500): string | null {
  if (typeof value !== "string") return null;
  const t = value.trim();
  if (!t) return null;
  return t.length > max ? t.slice(0, max) : t;
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function warn(warnings: string[], message: string): void {
  warnings.push(message);
  if (process.env.NODE_ENV !== "production") {
    console.warn(`[build-recommendation] ${message}`);
  }
}

function normalizeStatKey(raw: unknown): string | null {
  const s = asString(raw, 64);
  if (!s) return null;
  if (STAT_KEYS.has(s)) return s;
  const aliased = STAT_ALIASES[s.toLowerCase()];
  if (aliased && STAT_KEYS.has(aliased)) return aliased;
  return null;
}

function parseRecommendationLevel(raw: unknown): GuideRecommendationLevel | null {
  const s = asString(raw, 64)?.toLowerCase();
  if (!s) return null;
  if (LEVEL_SET.has(s)) return s as GuideRecommendationLevel;
  return null;
}

function parseConditions(raw: unknown): string[] {
  return asArray(raw)
    .map((item) => asString(item, 200))
    .filter((item): item is string => Boolean(item))
    .slice(0, 8);
}

function splitLegacyWeaponPreference(raw: unknown): string[] {
  const s = asString(raw, 128);
  if (!s) return [];
  return s
    .split(/[,、/｜|\n]+/)
    .map((part) => part.trim())
    .filter((part) => part.length > 0 && part.length <= 64)
    .slice(0, 8);
}

function sourceKey(videoId: string, index: number): string {
  const safe = videoId.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 24) || `idx${index}`;
  return `source-${safe}`;
}

export function isSafeYoutubeSourceUrl(raw: string): boolean {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password) return false;
    const host = url.hostname.toLowerCase().replace(/\.$/, "");
    return (
      host === "youtube.com" ||
      host.endsWith(".youtube.com") ||
      host === "youtu.be"
    );
  } catch {
    return false;
  }
}

function collectSources(
  rawSources: unknown,
  warnings: string[],
): { sources: PublicSource[]; byKey: Map<string, PublicSource>; byVideoId: Map<string, PublicSource> } {
  const byKey = new Map<string, PublicSource>();
  const byVideoId = new Map<string, PublicSource>();
  const sources: PublicSource[] = [];

  asArray(rawSources).forEach((item, index) => {
    const map = asRecord(item);
    const videoId = asString(map.videoId, 32);
    const sourceUrl = asString(map.sourceUrl, 500);
    if (!videoId || !sourceUrl) {
      warn(warnings, `sources[${index}] skipped: missing videoId or sourceUrl`);
      return;
    }
    if (!isSafeYoutubeSourceUrl(sourceUrl)) {
      warn(warnings, `sources[${index}] skipped: unsafe sourceUrl`);
      return;
    }
    const id =
      asString(map.id, 64) ??
      sourceKey(videoId, index);
    if (byKey.has(id)) {
      warn(warnings, `sources duplicate id ${id} skipped`);
      return;
    }
    const source: PublicSource = {
      id,
      videoId,
      title: asString(map.title ?? map.videoTitle, 200) ?? "",
      channelId: asString(map.channelId, 64),
      channelTitle: asString(map.channelTitle ?? map.channelName, 200) ?? "",
      publishedAt: asString(map.publishedAt, 64),
      reviewedAt: asString(map.reviewedAt, 64),
      gameVersion: asString(map.gameVersion, 32),
      sourceUrl,
    };
    byKey.set(id, source);
    if (!byVideoId.has(videoId)) byVideoId.set(videoId, source);
    sources.push(source);
  });

  return { sources, byKey, byVideoId };
}

function resolveCitationId(
  raw: unknown,
  byKey: Map<string, PublicSource>,
  byVideoId: Map<string, PublicSource>,
  warnings: string[],
  path: string,
): string | null {
  if (raw == null) return null;
  if (typeof raw === "string") {
    const key = raw.trim();
    if (!key) return null;
    if (byKey.has(key)) return key;
    if (byVideoId.has(key)) return byVideoId.get(key)!.id;
    warn(warnings, `${path}: unresolved citation "${key}"`);
    return null;
  }
  const map = asRecord(raw);
  const citationId = asString(map.citationId ?? map.id, 64);
  if (citationId && byKey.has(citationId)) return citationId;
  const videoId = asString(map.videoId, 32);
  if (videoId && byVideoId.has(videoId)) return byVideoId.get(videoId)!.id;
  if (citationId || videoId) {
    warn(warnings, `${path}: unresolved citation object`);
  }
  return null;
}

function normalizeWeapons(
  structuredList: unknown,
  aliasList: unknown,
  legacyPreference: unknown,
  byKey: Map<string, PublicSource>,
  byVideoId: Map<string, PublicSource>,
  warnings: string[],
): PublicWeapon[] {
  const rawList = asArray(structuredList).length > 0 ? asArray(structuredList) : asArray(aliasList);
  const out: PublicWeapon[] = [];

  if (rawList.length > 0) {
    rawList.forEach((item, index) => {
      const map = asRecord(item);
      const originRaw = asString(map.dataOrigin, 32);
      // 自動抽出の言及は公開候補に含めない（管理者確認後に manual/structured へ昇格）
      if (originRaw === "evidence_mention") {
        warn(warnings, `weapons[${index}] skipped: evidence_mention not publishable`);
        return;
      }
      if (map.adminConfirmed === false) {
        warn(warnings, `weapons[${index}] skipped: not adminConfirmed`);
        return;
      }
      const weaponId = asString(map.weaponId ?? map.id, 64);
      const displayName = asString(map.displayName ?? map.name, 64);
      if (!weaponId && !displayName) {
        warn(warnings, `weapons[${index}] skipped: missing weaponId and displayName`);
        return;
      }
      const rank = asFiniteNumber(map.rank);
      out.push({
        weaponId,
        displayName,
        rank: rank != null && rank >= 1 ? Math.round(rank) : null,
        recommendationLevel: parseRecommendationLevel(map.recommendationLevel),
        reason: asString(map.reason, 500),
        conditions: parseConditions(map.conditions),
        role: asString(map.role, 64),
        citationId: resolveCitationId(
          map.citationId ?? map.source ?? map.citation,
          byKey,
          byVideoId,
          warnings,
          `weapons[${index}]`,
        ),
        dataOrigin:
          originRaw === "legacy_preference" ? "legacy_preference" : "structured",
      });
    });
    return out.slice(0, 12);
  }

  const names = splitLegacyWeaponPreference(legacyPreference);
  return names.map((name, index) => ({
    weaponId: null,
    displayName: name,
    rank: index + 1,
    recommendationLevel: null,
    reason: null,
    conditions: [],
    role: null,
    citationId: null,
    dataOrigin: "legacy_preference" as const,
  }));
}

function normalizeArtifactRecommendations(
  structuredList: unknown,
  aliasList: unknown,
  byKey: Map<string, PublicSource>,
  byVideoId: Map<string, PublicSource>,
  warnings: string[],
): PublicArtifactRecommendation[] {
  const rawList =
    asArray(structuredList).length > 0 ? asArray(structuredList) : asArray(aliasList);
  const out: PublicArtifactRecommendation[] = [];

  rawList.forEach((item, index) => {
    const map = asRecord(item);
    const originRaw = asString(map.dataOrigin, 32);
    if (originRaw === "evidence_mention") {
      warn(
        warnings,
        `artifactRecommendations[${index}] skipped: evidence_mention not publishable`,
      );
      return;
    }
    if (map.adminConfirmed === false) {
      warn(warnings, `artifactRecommendations[${index}] skipped: not adminConfirmed`);
      return;
    }
    const sets: PublicArtifactSetPart[] = [];
    asArray(map.sets).forEach((part, partIndex) => {
      const partMap = asRecord(part);
      const setId = asString(partMap.setId ?? partMap.id, 64);
      const pieces = asFiniteNumber(partMap.pieces);
      if (!setId || pieces == null) {
        warn(warnings, `artifactRecommendations[${index}].sets[${partIndex}] skipped`);
        return;
      }
      const rounded = Math.round(pieces);
      if (rounded !== 2 && rounded !== 4) {
        warn(
          warnings,
          `artifactRecommendations[${index}].sets[${partIndex}]: unusual pieces=${rounded}`,
        );
      }
      if (rounded <= 0) return;
      sets.push({ setId, pieces: rounded });
    });
    if (sets.length === 0) {
      warn(warnings, `artifactRecommendations[${index}] skipped: empty sets`);
      return;
    }
    const rank = asFiniteNumber(map.rank);
    out.push({
      sets: sets.slice(0, 4),
      rank: rank != null && rank >= 1 ? Math.round(rank) : null,
      recommendationLevel: parseRecommendationLevel(map.recommendationLevel),
      reason: asString(map.reason, 500),
      conditions: parseConditions(map.conditions),
      role: asString(map.role, 64),
      isAlternative: map.isAlternative === true,
      citationId: resolveCitationId(
        map.citationId ?? map.source ?? map.citation,
        byKey,
        byVideoId,
        warnings,
        `artifactRecommendations[${index}]`,
      ),
    });
  });

  return out.slice(0, 12);
}

function normalizeMainStats(
  raw: unknown,
  byKey: Map<string, PublicSource>,
  byVideoId: Map<string, PublicSource>,
  warnings: string[],
): PublicMainStat[] {
  const out: PublicMainStat[] = [];
  asArray(raw).forEach((item, index) => {
    const map = asRecord(item);
    const slot = asString(map.slot, 16);
    if (!slot || !SLOT_SET.has(slot)) {
      warn(warnings, `mainStats[${index}] skipped: invalid slot`);
      return;
    }
    let primary = asArray(map.primaryStats)
      .map((s) => asString(s, 64))
      .filter((s): s is string => Boolean(s));
    let alternative = asArray(map.alternativeStats)
      .map((s) => asString(s, 64))
      .filter((s): s is string => Boolean(s));
    if (primary.length === 0 && alternative.length === 0) {
      const legacy = asArray(map.stats)
        .map((s) => asString(s, 64))
        .filter((s): s is string => Boolean(s));
      if (legacy.length > 0) {
        primary = [legacy[0]!];
        alternative = legacy.slice(1);
      }
    }
    if (primary.length === 0) {
      warn(warnings, `mainStats[${index}] skipped: empty stats`);
      return;
    }
    const stats = [...primary, ...alternative].slice(0, 6);
    out.push({
      slot: slot as PublicMainStat["slot"],
      primaryStats: primary.slice(0, 4),
      alternativeStats: alternative.slice(0, 4),
      stats,
      condition: asString(map.condition, 500),
      citationId: resolveCitationId(
        map.citationId ?? map.source ?? map.citation,
        byKey,
        byVideoId,
        warnings,
        `mainStats[${index}]`,
      ),
    });
  });
  return out.slice(0, 6);
}

function normalizeRecommendedStats(
  recommendedStatsRaw: unknown,
  targetsRaw: unknown,
  byKey: Map<string, PublicSource>,
  byVideoId: Map<string, PublicSource>,
  warnings: string[],
): { recommendedStats: PublicRecommendedStat[]; targets: PublicTarget[] } {
  const recommendedStats: PublicRecommendedStat[] = [];
  const targets: PublicTarget[] = [];

  const fromRecommended = asArray(recommendedStatsRaw);
  if (fromRecommended.length > 0) {
    fromRecommended.forEach((item, index) => {
      const map = asRecord(item);
      const stat = normalizeStatKey(map.stat);
      if (!stat) {
        warn(warnings, `recommendedStats[${index}] skipped: unknown stat`);
        return;
      }
      const minimum = asFiniteNumber(map.minimum ?? map.min);
      const maximum = asFiniteNumber(map.maximum ?? map.max);
      const recommended = asFiniteNumber(map.recommended);
      let valueType = asString(map.valueType, 32) as PublicRecommendedStat["valueType"] | null;
      if (
        valueType !== "minimum" &&
        valueType !== "maximum" &&
        valueType !== "range" &&
        valueType !== "target" &&
        valueType !== "ratio"
      ) {
        if (minimum != null && maximum != null) valueType = "range";
        else if (minimum != null && recommended == null) valueType = "minimum";
        else if (maximum != null && recommended == null && minimum == null) {
          valueType = "maximum";
        } else valueType = "target";
      }
      const unit =
        map.unit === "flat" || map.unit === "percent"
          ? map.unit
          : null;
      if (valueType === "ratio") {
        const leftStat = normalizeStatKey(map.leftStat);
        const rightStat = normalizeStatKey(map.rightStat);
        const leftValue = asFiniteNumber(map.leftValue);
        const rightValue = asFiniteNumber(map.rightValue);
        if (!leftStat || !rightStat || leftValue == null || rightValue == null) {
          warn(warnings, `recommendedStats[${index}] skipped: invalid ratio`);
          return;
        }
        recommendedStats.push({
          stat,
          valueType: "ratio",
          leftStat,
          leftValue,
          rightStat,
          rightValue,
          unit,
          condition: asString(map.condition, 500),
          citationId: resolveCitationId(
            map.citationId ?? map.source ?? map.citation,
            byKey,
            byVideoId,
            warnings,
            `recommendedStats[${index}]`,
          ),
        });
        return;
      }
      recommendedStats.push({
        stat,
        valueType,
        minimum,
        maximum,
        recommended,
        unit,
        condition: asString(map.condition, 500),
        citationId: resolveCitationId(
          map.citationId ?? map.source ?? map.citation,
          byKey,
          byVideoId,
          warnings,
          `recommendedStats[${index}]`,
        ),
      });
      const target: PublicTarget = { stat };
      if (recommended != null) target.recommended = recommended;
      if (minimum != null) target.min = minimum;
      if (maximum != null) target.max = maximum;
      if (unit) target.unit = unit;
      targets.push(target);
    });
    return {
      recommendedStats: recommendedStats.slice(0, 20),
      targets: targets.slice(0, 20),
    };
  }

  asArray(targetsRaw).forEach((item, index) => {
    const map = asRecord(item);
    const stat = normalizeStatKey(map.stat);
    if (!stat) {
      warn(warnings, `targets[${index}] skipped: unknown stat`);
      return;
    }
    const recommended = asFiniteNumber(map.recommended);
    const min = asFiniteNumber(map.min);
    const max = asFiniteNumber(map.max);
    const unit =
      map.unit === "flat" || map.unit === "percent" ? map.unit : undefined;
    const target: PublicTarget = { stat };
    if (recommended != null) target.recommended = recommended;
    if (min != null) target.min = min;
    if (max != null) target.max = max;
    if (unit) target.unit = unit;
    targets.push(target);

    let valueType: PublicRecommendedStat["valueType"] = "target";
    if (min != null && max != null) valueType = "range";
    else if (min != null && recommended == null) valueType = "minimum";
    recommendedStats.push({
      stat,
      valueType,
      minimum: min,
      maximum: max,
      recommended,
      unit: unit ?? null,
      condition: asString(map.condition, 500),
      citationId: resolveCitationId(
        map.citationId ?? map.source ?? map.citation,
        byKey,
        byVideoId,
        warnings,
        `targets[${index}]`,
      ),
    });
  });

  return {
    recommendedStats: recommendedStats.slice(0, 20),
    targets: targets.slice(0, 20),
  };
}

function topLevelGameVersion(
  explicit: unknown,
  sources: PublicSource[],
): string | null {
  const top = asString(explicit, 32);
  const versions = new Set<string>();
  if (top && parseGameVersionParts(top)) versions.add(top);
  for (const s of sources) {
    if (s.gameVersion && parseGameVersionParts(s.gameVersion)) {
      versions.add(s.gameVersion);
    }
  }
  // 候補側にバージョンフィールドは現状なし。混在判定は sources 中心。
  if (versions.size === 1) return [...versions][0]!;
  if (versions.size > 1) return null;
  if (top && parseGameVersionParts(top)) return top;
  return null;
}

/**
 * 公開 API 用 DTO を正規化する。
 */
export function normalizePublicBuildRecommendation(input: NormalizeInput): NormalizeResult {
  const warnings: string[] = [];
  const structured = asRecord(input.structured);
  const context = asRecord(input.context);

  const { sources, byKey, byVideoId } = collectSources(input.sources, warnings);

  const weapons = normalizeWeapons(
    input.weapons ?? structured.weapons,
    input.weaponRecommendations ?? structured.weaponRecommendations,
    context.weaponPreference,
    byKey,
    byVideoId,
    warnings,
  );

  const artifactRecommendations = normalizeArtifactRecommendations(
    input.artifactRecommendations ?? structured.artifactRecommendations,
    input.artifactSets ?? structured.artifactSets,
    byKey,
    byVideoId,
    warnings,
  );

  const mainStats = normalizeMainStats(input.mainStats, byKey, byVideoId, warnings);
  const { recommendedStats, targets } = normalizeRecommendedStats(
    input.recommendedStats ?? structured.recommendedStats,
    input.targets,
    byKey,
    byVideoId,
    warnings,
  );

  const investmentPriority = parseInvestmentPriority(
    input.investmentPriority ??
      structured.investmentPriority ??
      context.investmentPriority,
  );

  const gameVersion = topLevelGameVersion(
    input.gameVersion ?? structured.gameVersion ?? context.gameVersion,
    sources,
  );

  const substatPriority = asArray(input.substatPriority)
    .map((item) => normalizeStatKey(item))
    .filter((item): item is string => Boolean(item))
    .slice(0, 10);

  const caveats = asArray(input.caveats)
    .map((item) => asString(item, 300))
    .filter((item): item is string => Boolean(item))
    .slice(0, 10);

  const evidence = asArray(input.evidence)
    .map((item) => {
      const map = asRecord(item);
      const videoId = asString(map.videoId, 32);
      const exactVisibleText = asString(map.exactVisibleText ?? map.snippet, 200);
      if (!videoId || !exactVisibleText) return null;
      return {
        fieldPath: asString(map.fieldPath, 64) ?? "visual",
        exactVisibleText,
        startSeconds: asFiniteNumber(map.startSeconds) ?? 0,
        endSeconds: asFiniteNumber(map.endSeconds) ?? 0,
        videoId,
      };
    })
    .filter((item): item is NonNullable<typeof item> => Boolean(item))
    .slice(0, 40);

  const origin =
    input.origin === "merged" ? "merged" : "single_video";

  const contextOut: Record<string, string> = {};
  const role = asString(context.role, 64);
  const teamArchetype = asString(context.teamArchetype, 64);
  const notes = asString(context.notes, 500);
  // 構造化 weapons がある場合は weaponPreference を出力しない（legacy 誘導を避ける）
  const weaponPreference =
    weapons.some((w) => w.dataOrigin === "structured")
      ? null
      : asString(context.weaponPreference, 128);
  if (role) contextOut.role = role;
  if (teamArchetype) contextOut.teamArchetype = teamArchetype;
  if (notes) contextOut.notes = notes;
  if (weaponPreference) contextOut.weaponPreference = weaponPreference;

  const data: Record<string, unknown> = {
    schemaVersion: PUBLIC_BUILD_RECOMMENDATION_SCHEMA_VERSION,
    characterId: asString(input.characterId, 64) ?? "",
    label: "動画内推奨目安",
    status: "published",
    origin,
    overallConfidence:
      typeof input.overallConfidence === "number" &&
      Number.isFinite(input.overallConfidence)
        ? Math.min(1, Math.max(0, input.overallConfidence))
        : 0,
    context: contextOut,
    weapons,
    artifactRecommendations,
    mainStats,
    recommendedStats,
    // 既存モバイル互換
    targets,
    substatPriority,
    caveats,
    lastVerifiedAt: input.lastVerifiedAt ?? null,
    publishedAt: input.publishedAt ?? null,
    updatedAt: input.updatedAt ?? input.publishedAt ?? input.lastVerifiedAt ?? null,
    sources,
    evidence,
  };

  if (investmentPriority) {
    data.investmentPriority = investmentPriority;
  }
  if (gameVersion) {
    data.gameVersion = gameVersion;
  }

  return { data, warnings };
}

/**
 * 映像証拠の weaponMentions → 要確認候補（公開しない）。
 */
export function extractPendingWeaponMentions(
  mentions: Array<{
    exactVisibleText?: string;
    normalizedWeaponId?: string | null;
    confidence?: number;
    videoId?: string;
  }>,
): Array<Record<string, unknown>> {
  const seen = new Set<string>();
  const out: Array<Record<string, unknown>> = [];
  for (const mention of mentions) {
    const weaponId = asString(mention.normalizedWeaponId, 64);
    const displayName = asString(mention.exactVisibleText, 64);
    const key = weaponId ?? displayName;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push({
      weaponId,
      displayName,
      confidence: mention.confidence ?? null,
      videoId: mention.videoId ?? null,
      dataOrigin: "evidence_mention",
      adminConfirmed: false,
      reviewRequired: true,
      needsRecommendationConfirm: true,
    });
    if (out.length >= 12) break;
  }
  return out;
}

/**
 * 聖遺物 mentions → 要確認（pieces は不明のまま。4セットと推測しない）。
 */
export function extractPendingArtifactMentions(
  mentions: Array<{
    exactVisibleText?: string;
    normalizedArtifactSetId?: string | null;
    confidence?: number;
    videoId?: string;
  }>,
): Array<Record<string, unknown>> {
  const seen = new Set<string>();
  const out: Array<Record<string, unknown>> = [];
  for (const mention of mentions) {
    const setId = asString(mention.normalizedArtifactSetId, 64);
    const displayName = asString(mention.exactVisibleText, 64);
    const key = setId ?? displayName;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push({
      setId,
      displayName,
      pieces: null,
      confidence: mention.confidence ?? null,
      videoId: mention.videoId ?? null,
      dataOrigin: "evidence_mention",
      adminConfirmed: false,
      reviewRequired: true,
      needsPieces: true,
    });
    if (out.length >= 12) break;
  }
  return out;
}

/** @deprecated 互換: pending へ移行 */
export function extractWeaponsFromMentions(
  mentions: Parameters<typeof extractPendingWeaponMentions>[0],
): Array<Record<string, unknown>> {
  return extractPendingWeaponMentions(mentions);
}

/** @deprecated 互換: pending へ移行。pieces は推測しない */
export function extractArtifactRecommendationsFromMentions(
  mentions: Parameters<typeof extractPendingArtifactMentions>[0],
): Array<Record<string, unknown>> {
  return extractPendingArtifactMentions(mentions);
}

export function buildStructuredPayload(input: {
  weapons?: unknown;
  artifactRecommendations?: unknown;
  investmentPriority?: unknown;
  gameVersion?: unknown;
  recommendedStats?: unknown;
  pendingMentions?: unknown;
  structuredReviewStatus?: unknown;
}): string {
  const payload: Record<string, unknown> = {};
  if (Array.isArray(input.weapons) && input.weapons.length > 0) {
    payload.weapons = input.weapons;
  }
  if (
    Array.isArray(input.artifactRecommendations) &&
    input.artifactRecommendations.length > 0
  ) {
    payload.artifactRecommendations = input.artifactRecommendations;
  }
  const priority = parseInvestmentPriority(input.investmentPriority);
  if (priority) payload.investmentPriority = priority;
  const ver = asString(input.gameVersion, 32);
  if (ver && parseGameVersionParts(ver)) payload.gameVersion = ver;
  if (Array.isArray(input.recommendedStats) && input.recommendedStats.length > 0) {
    payload.recommendedStats = input.recommendedStats;
  }
  if (input.pendingMentions && typeof input.pendingMentions === "object") {
    payload.pendingMentions = input.pendingMentions;
  }
  if (typeof input.structuredReviewStatus === "string") {
    payload.structuredReviewStatus = input.structuredReviewStatus;
  }
  return JSON.stringify(payload);
}

function safeParseJsonObject(raw: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    /* ignore */
  }
  return {};
}

/** 検証済み証拠から構造化候補を抽出（理由は捏造しない） */
export function buildStructuredPayloadFromEvidences(
  evidences: Array<{ videoId: string; normalizedPayload: string }>,
): string {
  const weaponMentions: Array<{
    exactVisibleText?: string;
    normalizedWeaponId?: string | null;
    videoId?: string;
  }> = [];
  const artifactMentions: Array<{
    exactVisibleText?: string;
    normalizedArtifactSetId?: string | null;
    videoId?: string;
  }> = [];

  for (const evidence of evidences) {
    const payload = safeParseJsonObject(evidence.normalizedPayload);
    const weapons = Array.isArray(payload.weaponMentions)
      ? payload.weaponMentions
      : [];
    const artifacts = Array.isArray(payload.artifactSetMentions)
      ? payload.artifactSetMentions
      : [];
    for (const mention of weapons) {
      if (mention && typeof mention === "object") {
        weaponMentions.push({
          ...(mention as object),
          videoId: evidence.videoId,
        });
      }
    }
    for (const mention of artifacts) {
      if (mention && typeof mention === "object") {
        artifactMentions.push({
          ...(mention as object),
          videoId: evidence.videoId,
        });
      }
    }
  }

  return buildStructuredPayload({
    // 正式候補は空のまま。言及は pendingMentions のみ（管理者確認前に公開しない）
    weapons: [],
    artifactRecommendations: [],
    pendingMentions: {
      weapons: extractPendingWeaponMentions(weaponMentions),
      artifactSets: extractPendingArtifactMentions(artifactMentions),
    },
    structuredReviewStatus: "review_required",
  });
}
