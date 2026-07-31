import type { Prisma } from "@prisma/client";
import { z } from "zod";
import type { ValidatedTranscriptClaim } from "./analysis-schema";
import type { CanonicalValidatedClaim } from "./canonical-analysis";

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

export type AutomaticRecommendationSnapshot = Readonly<{
  characterId: string;
  contextPayload: Prisma.InputJsonObject;
  mainStatsPayload: readonly Prisma.InputJsonObject[];
  priorityPayload: readonly string[];
  targetsPayload: readonly Prisma.InputJsonObject[];
  structuredPayload: Prisma.InputJsonObject;
  overallConfidence: number;
  notes: string;
  evidenceStartSeconds: number;
  evidenceEndSeconds: number;
}>;

export const automaticRecommendationSnapshotSchema = z
  .object({
    characterId: z.string().min(1).max(100),
    contextPayload: z.record(z.string(), z.unknown()),
    mainStatsPayload: z.array(z.record(z.string(), z.unknown())),
    priorityPayload: z.array(z.string()),
    targetsPayload: z.array(z.record(z.string(), z.unknown())),
    structuredPayload: z.record(z.string(), z.unknown()),
    overallConfidence: z.number().min(0).max(1),
    notes: z.string().max(2_000),
    evidenceStartSeconds: z.number().nonnegative(),
    evidenceEndSeconds: z.number().positive(),
  })
  .strict()
  .refine(
    (snapshot) =>
      snapshot.evidenceEndSeconds >= snapshot.evidenceStartSeconds,
    { message: "invalidEvidenceRange" },
  );

export class AutomaticSnapshotError extends Error {
  constructor(public readonly safeCode: string) {
    super(safeCode);
    this.name = "AutomaticSnapshotError";
  }
}

type AutomaticSnapshotClaim =
  | ValidatedTranscriptClaim
  | CanonicalValidatedClaim;

/**
 * Maps only locally validated fields. Evidence text is deliberately omitted:
 * the public snapshot carries source ids and timestamps, never transcript text.
 */
export function buildAutomaticRecommendationSnapshot(input: {
  characterId: string;
  videoId: string;
  claims: readonly AutomaticSnapshotClaim[];
  overallConfidence: number;
  publishedContentUpdatedAt: Date;
}): AutomaticRecommendationSnapshot {
  const citationId = `source-${input.videoId}`;
  const weapons: Prisma.InputJsonObject[] = [];
  const artifacts: Prisma.InputJsonObject[] = [];
  const mainStats = new Map<string, Prisma.InputJsonObject>();
  const priority: string[] = [];
  const targets: Prisma.InputJsonObject[] = [];
  const recommendedStats: Prisma.InputJsonObject[] = [];
  let investmentPriority: "high" | "medium" | "low" | undefined;

  for (const claim of input.claims) {
    switch (claim.kind) {
      case "weapon":
        if (!claim.entityId) throw new AutomaticSnapshotError("WEAPON_ID_REQUIRED");
        weapons.push({
          weaponId: claim.entityId,
          displayName: claim.value,
          rank: weapons.length + 1,
          recommendationLevel: "recommended",
          reason: claim.condition || "公式字幕の該当箇所で推奨",
          conditions: claim.condition ? [claim.condition] : [],
          role: null,
          citationId,
          dataOrigin: "structured",
        });
        break;
      case "artifact_set":
        if (!claim.entityId) {
          throw new AutomaticSnapshotError("ARTIFACT_SET_ID_REQUIRED");
        }
        artifacts.push({
          sets: [{ setId: claim.entityId, pieces: inferArtifactPieces(claim.value) }],
          rank: artifacts.length + 1,
          recommendationLevel: "recommended",
          reason: claim.condition || "公式字幕の該当箇所で推奨",
          conditions: claim.condition ? [claim.condition] : [],
          role: null,
          isAlternative: artifacts.length > 0,
          citationId,
        });
        break;
      case "main_stat":
        if (!claim.slot || !["sands", "goblet", "circlet"].includes(claim.slot)) {
          throw new AutomaticSnapshotError("MAIN_STAT_SLOT_INVALID");
        }
        mainStats.set(claim.slot, {
          slot: claim.slot,
          primaryStats: [claim.value],
          alternativeStats: [],
          stats: [claim.value],
          condition: claim.condition || null,
          citationId,
        });
        break;
      case "sub_stat":
        if (!claim.entityId || !STAT_KEYS.has(claim.entityId)) {
          throw new AutomaticSnapshotError("SUB_STAT_ID_INVALID");
        }
        if (!priority.includes(claim.entityId)) priority.push(claim.entityId);
        break;
      case "target": {
        if (!claim.entityId || !STAT_KEYS.has(claim.entityId)) {
          throw new AutomaticSnapshotError("TARGET_STAT_ID_INVALID");
        }
        const numeric = parseTarget(claim.value);
        targets.push({ stat: claim.entityId, ...numeric });
        recommendedStats.push({
          stat: claim.entityId,
          valueType:
            numeric.min != null && numeric.max != null ? "range" : "target",
          minimum: numeric.min ?? null,
          maximum: numeric.max ?? null,
          recommended: numeric.recommended ?? null,
          unit: numeric.unit,
          condition: claim.condition || null,
          citationId,
          leftStat: null,
          leftValue: null,
          rightStat: null,
          rightValue: null,
        });
        break;
      }
      case "investment": {
        const normalized = claim.value.toLowerCase();
        investmentPriority = normalized.includes("high")
          ? "high"
          : normalized.includes("low")
            ? "low"
            : "medium";
        break;
      }
    }
  }
  if (weapons.length === 0 && artifacts.length === 0 && mainStats.size === 0) {
    throw new AutomaticSnapshotError("NO_PUBLISHABLE_BUILD_CLAIMS");
  }
  return {
    characterId: input.characterId,
    contextPayload: {},
    mainStatsPayload: [...mainStats.values()],
    priorityPayload: priority,
    targetsPayload: targets,
    structuredPayload: {
      automationSourceVideoId: input.videoId,
      weapons,
      artifactRecommendations: artifacts,
      recommendedStats,
      ...(investmentPriority ? { investmentPriority } : {}),
      structuredReviewStatus: "automatic_strict",
      publishedContentUpdatedAt: input.publishedContentUpdatedAt.toISOString(),
    },
    overallConfidence: input.overallConfidence,
    notes: "公式字幕の検証済み単一ソースから自動生成",
    evidenceStartSeconds: Math.min(
      ...input.claims.map((claim) => claim.startSeconds),
    ),
    evidenceEndSeconds: Math.max(
      ...input.claims.map((claim) => claim.endSeconds),
    ),
  };
}

export function parseAutomaticRecommendationSnapshot(
  payload: string,
): AutomaticRecommendationSnapshot {
  return automaticRecommendationSnapshotSchema.parse(
    JSON.parse(payload),
  ) as AutomaticRecommendationSnapshot;
}

function inferArtifactPieces(value: string): number {
  const match = value.match(/(?:^|\D)([245])(?:\D|$)/);
  return match ? Number(match[1]) : 4;
}

function parseTarget(value: string): {
  recommended?: number;
  min?: number;
  max?: number;
  unit: "flat" | "percent";
} {
  const numbers = [...value.matchAll(/\d+(?:\.\d+)?/g)].map((match) =>
    Number(match[0]),
  );
  if (numbers.length === 0 || numbers.some((number) => !Number.isFinite(number))) {
    throw new AutomaticSnapshotError("TARGET_VALUE_INVALID");
  }
  const unit = value.includes("%") ? "percent" : "flat";
  return numbers.length >= 2
    ? { min: numbers[0], max: numbers[1], unit }
    : { recommended: numbers[0], unit };
}
