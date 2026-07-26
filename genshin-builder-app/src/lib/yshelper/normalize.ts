import { YshelperSchemaError } from "./schema";
import type {
  BattleContentType,
  CanonicalSourcePayload,
  NormalizedBattleCharacter,
  NormalizedBattleStats,
  NormalizedBattleTeam,
} from "./types";

export function normalizeCanonicalPayload(
  contentType: BattleContentType,
  payload: CanonicalSourcePayload,
): NormalizedBattleStats {
  const teams = mergeTeams(payload);
  const characters = normalizeCharacters(payload);
  return {
    source: "YShelper",
    contentType,
    schemaVersion: 1,
    sourceVersion: payload.sourceVersion,
    seasonId: payload.seasonId,
    sourceUpdatedAt: payload.sourceUpdatedAt,
    sampleSize: payload.sampleSize,
    // Do not persist arbitrary bridge metadata until an explicit allowlist is
    // documented for an operator-verified source response.
    metadata: {},
    teams,
    characters,
  };
}

export function createTeamKey(characterIds: readonly string[]): string {
  return [...characterIds].sort().join(":");
}

function mergeTeams(payload: CanonicalSourcePayload): NormalizedBattleTeam[] {
  const groups = new Map<string, NormalizedBattleTeam>();
  const countAvailability = new Map<string, boolean>();
  for (const source of payload.teams) {
    if (new Set(source.characters).size !== source.characters.length) {
      throw new YshelperSchemaError("teams.characters.duplicate");
    }
    const teamKey = createTeamKey(source.characters);
    const scopeKey = `${source.side ?? ""}|${source.stageKey ?? ""}`;
    const key = `${teamKey}|${scopeKey}`;
    const rate = normalizeRate(
      source.usageRate,
      payload.rateUnit,
      "teams.usageRate",
    );
    const existing = groups.get(key);
    if (!existing) {
      groups.set(key, {
        teamKey,
        members: [...source.characters],
        usageRate: rate,
        usageCount: source.usageCount,
        rank: source.rank,
        side: source.side,
        stageKey: source.stageKey,
        sampleSize: source.sampleSize,
        isResolved: true,
        sourceMetadata: {},
      });
      countAvailability.set(key, source.usageCount !== undefined);
      continue;
    }
    existing.usageRate = normalizeMergedRate(existing.usageRate + rate);
    const hasAllCounts =
      countAvailability.get(key) === true && source.usageCount !== undefined;
    countAvailability.set(key, hasAllCounts);
    existing.usageCount = hasAllCounts
      ? (existing.usageCount ?? 0) + (source.usageCount ?? 0)
      : undefined;
    existing.rank = minDefined(existing.rank, source.rank);
    existing.sampleSize = maxDefined(existing.sampleSize, source.sampleSize);
  }
  return [...groups.values()].sort(
    (left, right) =>
      right.usageRate - left.usageRate ||
      left.teamKey.localeCompare(right.teamKey) ||
      (left.side ?? "").localeCompare(right.side ?? "") ||
      (left.stageKey ?? "").localeCompare(right.stageKey ?? ""),
  );
}

function normalizeCharacters(
  payload: CanonicalSourcePayload,
): NormalizedBattleCharacter[] {
  const seen = new Set<string>();
  const characters = payload.characters.map((source) => {
    const scopeKey = source.side ?? "";
    const key = `${source.characterId}|${scopeKey}`;
    if (seen.has(key)) {
      throw new YshelperSchemaError("characters.characterId.duplicate");
    }
    seen.add(key);
    return {
      characterId: source.characterId,
      usageRate: normalizeRate(
        source.usageRate,
        payload.rateUnit,
        "characters.usageRate",
      ),
      usageCount: source.usageCount,
      rank: source.rank,
      side: source.side,
      ownershipRate:
        source.ownershipRate === undefined
          ? undefined
          : normalizeRate(
              source.ownershipRate,
              payload.rateUnit,
              "characters.ownershipRate",
            ),
      usageAmongOwnersRate:
        source.usageAmongOwnersRate === undefined
          ? undefined
          : normalizeRate(
              source.usageAmongOwnersRate,
              payload.rateUnit,
              "characters.usageAmongOwnersRate",
            ),
      sampleSize: source.sampleSize,
      isResolved: true,
    } satisfies NormalizedBattleCharacter;
  });
  return characters.sort(
    (left, right) =>
      right.usageRate - left.usageRate ||
      left.characterId.localeCompare(right.characterId) ||
      (left.side ?? "").localeCompare(right.side ?? ""),
  );
}

function normalizeRate(
  value: number,
  unit: CanonicalSourcePayload["rateUnit"],
  field: string,
): number {
  const ratio = unit === "percent" ? value / 100 : value;
  if (!Number.isFinite(ratio) || ratio < 0 || ratio > 1) {
    throw new YshelperSchemaError(field);
  }
  return roundRate(ratio);
}

function normalizeMergedRate(value: number): number {
  if (!Number.isFinite(value) || value < 0 || value > 1 + 1e-9) {
    throw new YshelperSchemaError("teams.usageRate.duplicateTotal");
  }
  return roundRate(Math.min(1, value));
}

function roundRate(value: number): number {
  return Number(value.toFixed(8));
}

function minDefined(
  left: number | undefined,
  right: number | undefined,
): number | undefined {
  if (left === undefined) return right;
  if (right === undefined) return left;
  return Math.min(left, right);
}

function maxDefined(
  left: number | undefined,
  right: number | undefined,
): number | undefined {
  if (left === undefined) return right;
  if (right === undefined) return left;
  return Math.max(left, right);
}
