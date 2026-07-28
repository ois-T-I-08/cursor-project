/**
 * 構造化育成情報の管理用バリデーション・保存支援。
 */

import { fetchArtifactSets } from "@/lib/api/amber-details";
import { prisma } from "@/lib/db";
import {
  normalizePublicBuildRecommendation,
  parseGameVersionParts,
  parseInvestmentPriority,
} from "./public-recommendation-normalize";
import {
  publicBuildRecommendationSchema,
  type PublicBuildRecommendation,
} from "./visual-schemas";
import { getAllCharacters } from "@/lib/repository/characters";
import type { ArtifactSetMaster } from "./guide-admin-form";

export type ValidationIssue = {
  level: "error" | "warning";
  path: string;
  message: string;
};

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const t = value.trim();
  return t || null;
}

export async function listGuideMasterOptions(): Promise<{
  characters: Array<{ id: string; name: string; iconUrl: string; weaponType: string }>;
  weapons: Array<{ id: string; name: string; rarity: number; iconUrl: string; weaponType: string }>;
  artifactSets: ArtifactSetMaster[];
  mastersError: string | null;
}> {
  let mastersError: string | null = null;
  const [characters, weapons, artifactSetsRaw] = await Promise.all([
    getAllCharacters(),
    prisma.weapon.findMany({
      where: { rarity: { gte: 3 } },
      select: { id: true, name: true, rarity: true, iconUrl: true, weaponType: true },
      orderBy: [{ rarity: "desc" }, { name: "asc" }],
      take: 800,
    }),
    fetchArtifactSets().catch((error: unknown) => {
      mastersError =
        error instanceof Error ? error.message : "artifactSetsFetchFailed";
      return [] as Awaited<ReturnType<typeof fetchArtifactSets>>;
    }),
  ]);
  const artifactSets: ArtifactSetMaster[] = artifactSetsRaw.map((set) => ({
    setId: set.id,
    name: set.name,
    iconUrl: set.iconUrl,
    rarity: null,
    twoPieceEffect: set.effects[0] ?? "",
    fourPieceEffect: set.effects[1] ?? "",
    isAvailable: true,
  }));
  if (artifactSets.length === 0 && !mastersError) {
    mastersError = "artifactSetsEmpty";
  }
  return {
    characters: characters.map((c) => ({
      id: c.id,
      name: c.name,
      iconUrl: c.iconUrl ?? "",
      weaponType: String(c.weaponType),
    })),
    weapons,
    artifactSets,
    mastersError,
  };
}

/** 下書き保存時: 警告中心。致命的な型崩れのみ error */
export function validateStructuredDraft(input: {
  characterId: string;
  structured: Record<string, unknown>;
  mainStats?: unknown;
  targets?: unknown;
  knownWeaponIds?: Set<string>;
  knownSetIds?: Set<string>;
}): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!asString(input.characterId)) {
    issues.push({ level: "error", path: "characterId", message: "キャラクターIDが必要です" });
  }

  const priority = input.structured.investmentPriority;
  if (priority != null && parseInvestmentPriority(priority) == null) {
    issues.push({
      level: "error",
      path: "investmentPriority",
      message: "育成優先度が不正です（high/medium/low/未設定）",
    });
  }

  const gameVersion = asString(input.structured.gameVersion);
  if (gameVersion && !parseGameVersionParts(gameVersion)) {
    issues.push({
      level: "warning",
      path: "gameVersion",
      message: "ゲームバージョンを解析できません",
    });
  }

  asArray(input.structured.weapons).forEach((item, index) => {
    const map = asRecord(item);
    if (map.dataOrigin === "evidence_mention" || map.adminConfirmed === false) {
      issues.push({
        level: "warning",
        path: `weapons[${index}]`,
        message: "自動抽出の言及です。公開前に確認・昇格が必要です",
      });
    }
    const weaponId = asString(map.weaponId);
    if (weaponId && input.knownWeaponIds && !input.knownWeaponIds.has(weaponId)) {
      issues.push({
        level: "warning",
        path: `weapons[${index}].weaponId`,
        message: `未知の武器ID: ${weaponId}`,
      });
    }
    if (!asString(map.reason)) {
      issues.push({
        level: "warning",
        path: `weapons[${index}].reason`,
        message: "推奨理由が未入力です",
      });
    }
  });

  asArray(input.structured.artifactRecommendations).forEach((item, index) => {
    const map = asRecord(item);
    if (map.dataOrigin === "evidence_mention" || map.adminConfirmed === false) {
      issues.push({
        level: "warning",
        path: `artifactRecommendations[${index}]`,
        message: "自動抽出または未確認の候補です",
      });
    }
    const sets = asArray(map.sets);
    if (sets.length === 0) {
      issues.push({
        level: "warning",
        path: `artifactRecommendations[${index}].sets`,
        message: "セット構成が空です（下書き保存可・公開不可）",
      });
      return;
    }
    let total = 0;
    sets.forEach((part, partIndex) => {
      const p = asRecord(part);
      const pieces = typeof p.pieces === "number" ? p.pieces : null;
      if (pieces == null) {
        issues.push({
          level: "warning",
          path: `artifactRecommendations[${index}].sets[${partIndex}].pieces`,
          message: "pieces が未設定です（要確認。4セットへ勝手に確定しません）",
        });
      } else if (pieces !== 2 && pieces !== 4) {
        issues.push({
          level: "error",
          path: `artifactRecommendations[${index}].sets[${partIndex}].pieces`,
          message: "pieces は 2 または 4 である必要があります",
        });
      } else {
        total += pieces;
      }
      const setId = asString(p.setId);
      if (!setId) {
        issues.push({
          level: "warning",
          path: `artifactRecommendations[${index}].sets[${partIndex}].setId`,
          message: "setId が未入力です",
        });
      } else if (input.knownSetIds && input.knownSetIds.size > 0 && !input.knownSetIds.has(setId)) {
        issues.push({
          level: "warning",
          path: `artifactRecommendations[${index}].sets[${partIndex}].setId`,
          message: `マスター未登録の聖遺物セット: ${setId}`,
        });
      }
    });
    if (map.compositionMode === "undetermined" || sets.some((s) => asRecord(s).pieces == null)) {
      issues.push({
        level: "warning",
        path: `artifactRecommendations[${index}]`,
        message: "聖遺物構成が未確定です（下書き可・公開不可）",
      });
    }
    if (sets.length === 1 && total === 4) {
      /* ok 4pc */
    } else if (sets.length === 2 && total === 4) {
      const ids = sets.map((s) => asString(asRecord(s).setId));
      if (ids[0] && ids[0] === ids[1]) {
        issues.push({
          level: "warning",
          path: `artifactRecommendations[${index}].sets`,
          message: "同一セットの 2+2 です。意図を確認してください",
        });
      }
    } else if (sets.length > 0 && total > 0) {
      issues.push({
        level: "warning",
        path: `artifactRecommendations[${index}].sets`,
        message: `部位数の合計が不自然です（合計 ${total}）`,
      });
    }
  });

  const pending = asRecord(input.structured.pendingMentions);
  if (asArray(pending.weapons).length > 0 || asArray(pending.artifactSets).length > 0) {
    issues.push({
      level: "warning",
      path: "pendingMentions",
      message: "未確認の映像言及があります。公開前に昇格または破棄してください",
    });
  }

  asArray(input.mainStats).forEach((item, index) => {
    const map = asRecord(item);
    const primary = asArray(map.primaryStats).map(asString).filter(Boolean);
    const alt = asArray(map.alternativeStats).map(asString).filter(Boolean);
    for (const s of primary) {
      if (alt.includes(s)) {
        issues.push({
          level: "warning",
          path: `mainStats[${index}]`,
          message: `primary と alternative に同一値があります: ${s}`,
        });
      }
    }
  });

  asArray(input.targets).forEach((item, index) => {
    const map = asRecord(item);
    const min = typeof map.min === "number" ? map.min : typeof map.minimum === "number" ? map.minimum : null;
    const max = typeof map.max === "number" ? map.max : typeof map.maximum === "number" ? map.maximum : null;
    if (min != null && max != null && min > max) {
      issues.push({
        level: "error",
        path: `targets[${index}]`,
        message: "minimum が maximum を超えています",
      });
    }
  });

  asArray(input.structured.recommendedStats).forEach((item, index) => {
    const map = asRecord(item);
    if (map.valueType === "ratio") {
      issues.push({
        level: "warning",
        path: `recommendedStats[${index}]`,
        message:
          "ratio（比率）は現在のモバイル版では表示されない可能性があります（公開は警告のみ）",
      });
    }
    const min =
      typeof map.minimum === "number"
        ? map.minimum
        : typeof map.min === "number"
          ? map.min
          : null;
    const max =
      typeof map.maximum === "number"
        ? map.maximum
        : typeof map.max === "number"
          ? map.max
          : null;
    if (min != null && max != null && min > max) {
      issues.push({
        level: "error",
        path: `recommendedStats[${index}]`,
        message: "minimum が maximum を超えています",
      });
    }
  });

  return issues;
}

/** 公開時: error があれば拒否 */
export function validateStructuredForPublish(input: {
  characterId: string;
  structured: Record<string, unknown>;
  mainStats?: unknown;
  targets?: unknown;
  sources?: unknown;
  knownWeaponIds?: Set<string>;
  knownSetIds?: Set<string>;
}): ValidationIssue[] {
  const issues = validateStructuredDraft(input);
  const pending = asRecord(input.structured.pendingMentions);
  if (asArray(pending.weapons).length > 0 || asArray(pending.artifactSets).length > 0) {
    issues.push({
      level: "error",
      path: "pendingMentions",
      message: "未確認の映像言及が残っているため公開できません",
    });
  }

  asArray(input.structured.weapons).forEach((item, index) => {
    const map = asRecord(item);
    if (map.dataOrigin === "evidence_mention" || map.adminConfirmed === false) {
      issues.push({
        level: "error",
        path: `weapons[${index}]`,
        message: "未確認の武器候補は公開できません",
      });
    }
    const weaponId = asString(map.weaponId);
    if (weaponId && input.knownWeaponIds && !input.knownWeaponIds.has(weaponId)) {
      issues.push({
        level: "error",
        path: `weapons[${index}].weaponId`,
        message: `不正な武器ID: ${weaponId}`,
      });
    }
  });

  asArray(input.structured.artifactRecommendations).forEach((item, index) => {
    const map = asRecord(item);
    if (map.dataOrigin === "evidence_mention" || map.adminConfirmed === false) {
      issues.push({
        level: "error",
        path: `artifactRecommendations[${index}]`,
        message: "未確認の聖遺物候補は公開できません",
      });
    }
    const sets = asArray(map.sets);
    if (sets.length === 0) {
      issues.push({
        level: "error",
        path: `artifactRecommendations[${index}].sets`,
        message: "セット構成が空のため公開できません",
      });
    }
    let total = 0;
    if (map.compositionMode === "undetermined") {
      issues.push({
        level: "error",
        path: `artifactRecommendations[${index}]`,
        message: "未確定の聖遺物構成は公開できません",
      });
    }
    for (const [partIndex, part] of sets.entries()) {
      const p = asRecord(part);
      const setId = asString(p.setId);
      if (!setId) {
        issues.push({
          level: "error",
          path: `artifactRecommendations[${index}].sets[${partIndex}].setId`,
          message: "公開には setId が必要です",
        });
      } else if (input.knownSetIds && input.knownSetIds.size > 0 && !input.knownSetIds.has(setId)) {
        issues.push({
          level: "error",
          path: `artifactRecommendations[${index}].sets[${partIndex}].setId`,
          message: `マスターに存在しない setId: ${setId}`,
        });
      }
      const pieces = typeof p.pieces === "number" ? p.pieces : null;
      if (pieces !== 2 && pieces !== 4) {
        issues.push({
          level: "error",
          path: `artifactRecommendations[${index}].sets[${partIndex}]`,
          message: "公開には pieces=2 または 4 が必要です（未確定構成は不可）",
        });
      } else {
        total += pieces;
      }
    }
    if (sets.length === 1 && total === 4) {
      /* ok */
    } else if (sets.length === 2 && total === 4) {
      /* ok 2+2 */
    } else if (sets.length > 0) {
      issues.push({
        level: "error",
        path: `artifactRecommendations[${index}].sets`,
        message: "公開可能なセット構成ではありません（4セットまたは 2+2）",
      });
    }
  });

  const citationIds = new Set(
    asArray(input.sources)
      .map((s) => asString(asRecord(s).id))
      .filter((id): id is string => Boolean(id)),
  );
  const checkCitation = (raw: unknown, path: string) => {
    const id = asString(raw);
    if (!id) return;
    if (citationIds.size > 0 && !citationIds.has(id)) {
      issues.push({
        level: "error",
        path,
        message: `解決不能な citationId: ${id}`,
      });
    }
  };
  for (const [i, w] of asArray(input.structured.weapons).entries()) {
    checkCitation(asRecord(w).citationId, `weapons[${i}].citationId`);
  }
  for (const [i, a] of asArray(input.structured.artifactRecommendations).entries()) {
    checkCitation(asRecord(a).citationId, `artifactRecommendations[${i}].citationId`);
  }

  if (input.structured.structuredReviewStatus === "review_required") {
    issues.push({
      level: "error",
      path: "structuredReviewStatus",
      message: "構造化レビューが未完了です（承認前に確認を完了してください）",
    });
  }

  return issues;
}

export function previewNormalizedRecommendation(input: {
  characterId: string;
  origin?: string;
  overallConfidence?: number;
  context?: unknown;
  mainStats?: unknown;
  substatPriority?: unknown;
  targets?: unknown;
  structured?: Record<string, unknown>;
  sources?: unknown;
  evidence?: unknown;
  lastVerifiedAt?: string | null;
  publishedAt?: string | null;
  updatedAt?: string | null;
}): {
  data: PublicBuildRecommendation | null;
  warnings: string[];
  parseError: string | null;
} {
  const structured = input.structured ?? {};
  const { data, warnings } = normalizePublicBuildRecommendation({
    characterId: input.characterId,
    origin: input.origin,
    overallConfidence: input.overallConfidence,
    context: asRecord(input.context),
    mainStats: input.mainStats ?? [],
    substatPriority: input.substatPriority ?? [],
    targets: input.targets ?? [],
    structured,
    weapons: structured.weapons,
    artifactRecommendations: structured.artifactRecommendations,
    investmentPriority: structured.investmentPriority,
    gameVersion: structured.gameVersion,
    recommendedStats: structured.recommendedStats,
    sources: input.sources ?? [],
    evidence: input.evidence ?? [],
    lastVerifiedAt: input.lastVerifiedAt ?? null,
    publishedAt: input.publishedAt ?? new Date().toISOString(),
    updatedAt: input.updatedAt ?? new Date().toISOString(),
  });

  try {
    const parsed = publicBuildRecommendationSchema.parse(data);
    return { data: parsed, warnings, parseError: null };
  } catch (error) {
    return {
      data: null,
      warnings,
      parseError: error instanceof Error ? error.message : "invalidPublicDto",
    };
  }
}

export function collectCitationIdsFromStructured(
  structured: Record<string, unknown>,
): string[] {
  const ids = new Set<string>();
  for (const listKey of ["weapons", "artifactRecommendations"] as const) {
    for (const item of asArray(structured[listKey])) {
      const id = asString(asRecord(item).citationId);
      if (id) ids.add(id);
    }
  }
  for (const item of asArray(structured.recommendedStats)) {
    const id = asString(asRecord(item).citationId);
    if (id) ids.add(id);
  }
  return [...ids];
}
