import {
  STAT_KEYS,
  VISUAL_VALUE_PURPOSES,
  videoVisualAnalysisResultSchema,
  type VideoVisualAnalysisResult,
} from "./visual-schemas";

const PURPOSE_SET = new Set<string>(VISUAL_VALUE_PURPOSES);

const STAT_ALIASES: Record<string, (typeof STAT_KEYS)[number]> = {
  hp: "hp",
  atk: "atk",
  attack: "atk",
  def: "def",
  defense: "def",
  em: "em",
  elementalmastery: "em",
  critrate: "critRate",
  crit_rate: "critRate",
  cr: "critRate",
  critdmg: "critDmg",
  crit_dmg: "critDmg",
  critdamage: "critDmg",
  cd: "critDmg",
  er: "er",
  energyrecharge: "er",
  recharge: "er",
  healing: "healing",
  healingbonus: "healing",
  elemdmg: "elemDmg",
  elementaldamage: "elemDmg",
  dmgbonus: "elemDmg",
  physdmg: "physDmg",
  physicaldamage: "physDmg",
};

const PURPOSE_ALIASES: Record<string, (typeof VISUAL_VALUE_PURPOSES)[number]> = {
  explicit_recommendation: "explicit_recommendation",
  recommendation: "explicit_recommendation",
  recommended: "explicit_recommendation",
  minimum_requirement: "minimum_requirement",
  minimum: "minimum_requirement",
  min: "minimum_requirement",
  comfortable_target: "comfortable_target",
  target: "comfortable_target",
  recommended_range: "recommended_range",
  range: "recommended_range",
  example_build: "example_build",
  example: "example_build",
  creator_current_build: "creator_current_build",
  current_build: "creator_current_build",
  creator_build: "creator_current_build",
  comparison_build: "comparison_build",
  comparison: "comparison_build",
  damage_test_build: "damage_test_build",
  damage_test: "damage_test_build",
  before_after_comparison: "before_after_comparison",
  unknown: "unknown",
};

const EVIDENCE_TYPE_ALIASES: Record<string, string> = {
  recommendation_table: "recommendation_table",
  build_summary_slide: "build_summary_slide",
  character_status_screen: "character_status_screen",
  status_screen: "character_status_screen",
  artifact_screen: "artifact_screen",
  weapon_screen: "weapon_screen",
  comparison_table: "comparison_table",
  on_screen_text: "on_screen_text",
  text: "on_screen_text",
  unreadable: "unreadable",
  other: "other",
  table: "recommendation_table",
  slide: "build_summary_slide",
};

const TEXT_CATEGORY_ALIASES: Record<string, string> = {
  stat_label: "stat_label",
  stat_value: "stat_value",
  weapon_name: "weapon_name",
  artifact_set: "artifact_set",
  main_stat: "main_stat",
  substat_priority: "substat_priority",
  condition: "condition",
  heading: "heading",
  other: "other",
  label: "stat_label",
  value: "stat_value",
  on_screen_text: "other",
  text: "other",
};

/**
 * Soft-normalize Gemini JSON before strict Zod parse.
 * Does not invent stats; only coerces shapes / aliases / drops invalid rows.
 */
export function normalizeGeminiVisualPayload(
  raw: unknown,
  expectedVideoId: string,
): unknown {
  // Gemini が単一オブジェクトを配列で包むことがある
  if (Array.isArray(raw)) {
    if (raw.length === 0) {
      return {
        videoId: expectedVideoId,
        relevant: false,
        detectedCharacterIds: [],
        evidences: [],
        unresolvedEntities: [],
        analysisSummary: "empty_array_payload",
      };
    }
    if (raw.length === 1) {
      return normalizeGeminiVisualPayload(raw[0], expectedVideoId);
    }
    const merged = raw
      .map((item) => normalizeGeminiVisualPayload(item, expectedVideoId))
      .filter(isRecord);
    if (merged.length === 0) return raw;
    const evidences = merged
      .flatMap((item) => (Array.isArray(item.evidences) ? item.evidences : []))
      .slice(0, 80);
    const detectedCharacterIds = [
      ...new Set(
        merged.flatMap((item) =>
          Array.isArray(item.detectedCharacterIds)
            ? item.detectedCharacterIds.map(String)
            : [],
        ),
      ),
    ].slice(0, 20);
    const unresolvedEntities = merged
      .flatMap((item) =>
        Array.isArray(item.unresolvedEntities) ? item.unresolvedEntities : [],
      )
      .slice(0, 40);
    return {
      videoId: expectedVideoId,
      relevant: merged.some((item) => Boolean(item.relevant)) || evidences.length > 0,
      detectedCharacterIds,
      evidences,
      unresolvedEntities,
      analysisSummary: merged
        .map((item) => String(item.analysisSummary ?? ""))
        .filter(Boolean)
        .join(" | ")
        .slice(0, 1000),
    };
  }

  if (!isRecord(raw)) return raw;
  const evidencesIn = Array.isArray(raw.evidences) ? raw.evidences : [];
  const evidences = evidencesIn
    .map((item) => normalizeEvidence(item, expectedVideoId))
    .filter((item): item is Record<string, unknown> => item != null)
    .slice(0, 80);

  const detected = normalizeIdList(raw.detectedCharacterIds).slice(0, 20);
  const unresolved = (
    Array.isArray(raw.unresolvedEntities) ? raw.unresolvedEntities : []
  )
    .map(normalizeUnresolved)
    .filter((item): item is Record<string, unknown> => item != null)
    .slice(0, 40);

  return {
    videoId: String(raw.videoId ?? expectedVideoId).slice(0, 32),
    relevant: Boolean(raw.relevant ?? evidences.length > 0),
    detectedCharacterIds: detected,
    evidences,
    unresolvedEntities: unresolved,
    analysisSummary: String(raw.analysisSummary ?? "").slice(0, 1000),
  };
}

export function parseGeminiVisualResult(
  raw: unknown,
  expectedVideoId: string,
): VideoVisualAnalysisResult {
  const normalized = normalizeGeminiVisualPayload(raw, expectedVideoId);
  const parsed = videoVisualAnalysisResultSchema.safeParse(normalized);
  if (parsed.success) return parsed.data;

  const firstPath = parsed.error.issues[0]?.path.join(".") || "unknown";
  return videoVisualAnalysisResultSchema.parse({
    videoId: expectedVideoId,
    relevant: false,
    detectedCharacterIds: [],
    evidences: [],
    unresolvedEntities: [],
    analysisSummary: `schema_partial_drop:${firstPath}`.slice(0, 1000),
  });
}

function normalizeEvidence(
  raw: unknown,
  expectedVideoId: string,
): Record<string, unknown> | null {
  if (!isRecord(raw)) return null;
  const startSeconds = coerceNonNegativeNumber(raw.startSeconds);
  const endSeconds = coerceNonNegativeNumber(raw.endSeconds);
  if (startSeconds == null || endSeconds == null) return null;
  if (startSeconds > endSeconds) return null;

  const evidenceType =
    EVIDENCE_TYPE_ALIASES[normalizeKey(String(raw.evidenceType ?? "other"))] ??
    "other";

  const visibleTexts = (
    Array.isArray(raw.visibleTexts) ? raw.visibleTexts : []
  )
    .map(normalizeVisibleText)
    .filter((item): item is Record<string, unknown> => item != null)
    .slice(0, 100);

  const statValues = (Array.isArray(raw.statValues) ? raw.statValues : [])
    .map(normalizeStatValue)
    .filter((item): item is Record<string, unknown> => item != null)
    .slice(0, 30);

  const confidence = coerceConfidence(raw.confidence) ?? 0.5;
  const readable =
    typeof raw.readable === "boolean"
      ? raw.readable
      : evidenceType !== "unreadable";

  return {
    videoId: String(raw.videoId ?? expectedVideoId).slice(0, 32),
    startSeconds,
    endSeconds,
    evidenceType,
    targetCharacterIds: normalizeIdList(raw.targetCharacterIds).slice(0, 10),
    visibleTexts,
    statValues,
    recommendedMainStats: normalizeMainStats(raw.recommendedMainStats),
    statPriority: stringArray(raw.statPriority, 20, 100),
    weaponMentions: normalizeMentions(raw.weaponMentions, "normalizedWeaponId"),
    artifactSetMentions: normalizeMentions(
      raw.artifactSetMentions,
      "normalizedArtifactSetId",
    ),
    visualSummary: String(raw.visualSummary ?? "").slice(0, 500),
    confidence,
    readable,
    warnings: stringArray(raw.warnings, 20, 300),
  };
}

function normalizeStatValue(raw: unknown): Record<string, unknown> | null {
  if (!isRecord(raw)) return null;
  const statKey = mapStatKey(raw.statKey);
  if (!statKey) return null;
  const purpose =
    PURPOSE_ALIASES[normalizeKey(String(raw.purpose ?? "unknown"))] ?? "unknown";
  if (!PURPOSE_SET.has(purpose)) return null;

  const exactVisibleText = String(raw.exactVisibleText ?? "").trim().slice(0, 200);
  if (!exactVisibleText) return null;

  const unit =
    String(raw.unit ?? "").toLowerCase() === "flat" ? "flat" : "percent";
  const confidence = coerceConfidence(raw.confidence);
  if (confidence == null) return null;

  return {
    statKey,
    unit,
    minimum: coerceNullableNumber(raw.minimum),
    recommended: coerceNullableNumber(raw.recommended),
    maximum: coerceNullableNumber(raw.maximum),
    purpose,
    exactVisibleText,
    condition: String(raw.condition ?? "").slice(0, 500),
    confidence,
  };
}

function normalizeVisibleText(raw: unknown): Record<string, unknown> | null {
  if (!isRecord(raw)) return null;
  const text = String(raw.text ?? "").trim().slice(0, 300);
  if (!text) return null;
  const confidence = coerceConfidence(raw.confidence);
  if (confidence == null) return null;
  const category =
    TEXT_CATEGORY_ALIASES[normalizeKey(String(raw.category ?? "other"))] ??
    "other";
  return { text, confidence, category };
}

function normalizeUnresolved(raw: unknown): Record<string, unknown> | null {
  if (!isRecord(raw)) return null;
  const exactVisibleText = String(raw.exactVisibleText ?? "")
    .trim()
    .slice(0, 100);
  if (!exactVisibleText) return null;
  const timestampSeconds = coerceNonNegativeNumber(raw.timestampSeconds);
  if (timestampSeconds == null) return null;
  const typeRaw = normalizeKey(String(raw.type ?? "other"));
  const type = ["character", "weapon", "artifact_set", "stat", "other"].includes(
    typeRaw,
  )
    ? typeRaw
    : "other";
  return { exactVisibleText, type, timestampSeconds };
}

function normalizeMentions(
  raw: unknown,
  idKey: "normalizedWeaponId" | "normalizedArtifactSetId",
): Array<Record<string, unknown>> {
  if (!Array.isArray(raw)) return [];
  const out: Array<Record<string, unknown>> = [];
  for (const item of raw.slice(0, 20)) {
    if (!isRecord(item)) continue;
    const exactVisibleText = String(item.exactVisibleText ?? "")
      .trim()
      .slice(0, 100);
    if (!exactVisibleText) continue;
    const confidence = coerceConfidence(item.confidence) ?? 0;
    const idRaw = item[idKey];
    const normalizedId =
      idRaw == null || idRaw === ""
        ? null
        : String(idRaw).slice(0, 64).match(/^[a-z0-9][a-z0-9_-]{0,63}$/i)
          ? String(idRaw).slice(0, 64)
          : null;
    out.push({
      exactVisibleText,
      [idKey]: normalizedId,
      confidence,
    });
  }
  return out;
}

function normalizeMainStats(raw: unknown): Record<string, string[]> | null {
  if (raw == null) return null;
  if (Array.isArray(raw)) {
    const sands: string[] = [];
    const goblet: string[] = [];
    const circlet: string[] = [];
    for (const item of raw.slice(0, 12)) {
      if (!isRecord(item)) continue;
      const slot = normalizeKey(String(item.slot ?? ""));
      const keys = stringArray(
        item.statKeys ?? item.stats ?? item.values,
        5,
        64,
      ).map((key) => mapStatKey(key) ?? key);
      if (slot === "sands" || slot === "時計" || slot === "clock") sands.push(...keys);
      else if (slot === "goblet" || slot === "杯" || slot === "cup") goblet.push(...keys);
      else if (slot === "circlet" || slot === "冠" || slot === "crown") {
        circlet.push(...keys);
      }
    }
    if (sands.length === 0 && goblet.length === 0 && circlet.length === 0) {
      return null;
    }
    return {
      sands: [...new Set(sands)].slice(0, 5),
      goblet: [...new Set(goblet)].slice(0, 5),
      circlet: [...new Set(circlet)].slice(0, 5),
    };
  }
  if (!isRecord(raw)) return null;
  return {
    sands: stringArray(raw.sands, 5, 64),
    goblet: stringArray(raw.goblet, 5, 64),
    circlet: stringArray(raw.circlet, 5, 64),
  };
}

function mapStatKey(raw: unknown): (typeof STAT_KEYS)[number] | null {
  const key = normalizeKey(String(raw ?? ""));
  if (STAT_ALIASES[key]) return STAT_ALIASES[key];
  for (const statKey of STAT_KEYS) {
    if (statKey.toLowerCase() === key) return statKey;
  }
  return null;
}

function normalizeIdList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const item of raw) {
    const id = String(item ?? "").trim();
    if (/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(id)) out.push(id.slice(0, 64));
  }
  return [...new Set(out)];
}

function stringArray(raw: unknown, maxItems: number, maxLen: number): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => String(item ?? "").trim().slice(0, maxLen))
    .filter(Boolean)
    .slice(0, maxItems);
}

function coerceConfidence(raw: unknown): number | null {
  const n = coerceNumber(raw);
  if (n == null) return null;
  if (n > 1 && n <= 100) return Math.min(1, n / 100);
  if (n < 0 || n > 1) return null;
  return n;
}

function coerceNullableNumber(raw: unknown): number | null {
  if (raw == null || raw === "") return null;
  const n = coerceNumber(raw);
  if (n == null || !Number.isFinite(n) || n < 0 || n > 1_000_000) return null;
  return n;
}

function coerceNonNegativeNumber(raw: unknown): number | null {
  const n = coerceNumber(raw);
  if (n == null || !Number.isFinite(n) || n < 0) return null;
  return n;
}

function coerceNumber(raw: unknown): number | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const timestamp = parseTimestamp(trimmed);
  if (timestamp != null) return timestamp;
  const cleaned = trimmed.replace(/[%％,]/g, "");
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

function parseTimestamp(value: string): number | null {
  const match = value.match(/^(\d{1,2}):([0-5]\d)(?::([0-5]\d))?$/);
  if (!match) return null;
  if (match[3] != null) {
    return (
      Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3])
    );
  }
  return Number(match[1]) * 60 + Number(match[2]);
}

function normalizeKey(value: string): string {
  return value.trim().toLowerCase().replace(/[\s-]+/g, "_");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value != null && !Array.isArray(value);
}
