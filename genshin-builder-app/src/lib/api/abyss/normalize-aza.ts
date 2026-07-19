import type {
  AbyssArtifactStatistic,
  AbyssCharacterStatistic,
  AbyssConstellationStatistic,
  AbyssRateStatistic,
  AbyssStatisticsSnapshot,
  AbyssTeamStatistic,
} from "@/lib/abyss/types";
import { AbyssStatisticsError } from "./errors";

const CHARACTER_LIMIT = 256;
const TEAM_LIMIT_PER_HALF = 200;
const INPUT_TEAM_LIMIT_PER_HALF = 1_000;
const EQUIPMENT_LIMIT = 128;
const ARTIFACT_LIMIT = 64;
const CHARACTER_ID = /^\d{8,16}$/;
const EQUIPMENT_ID = /^\d{4,16}$/;
const API_VERSION = /^[A-Za-z0-9._-]{1,32}$/;

export function normalizeAzaAbyssStatistics(
  input: Record<string, unknown>,
): AbyssStatisticsSnapshot {
  if (input.retcode !== 0) invalid();
  const meta = object(input.meta);
  const data = object(input.data);
  const schedule = object(data.schedule);

  const sourceApiVersion = string(meta.api_ver, API_VERSION);
  const scheduleId = integer(schedule.id, 0, 1_000_000);
  const periodStart = unixSeconds(schedule.start_time);
  const periodEnd = unixSeconds(schedule.end_time);
  if (periodEnd <= periodStart) invalid();

  const sourceUpdatedAt = epochMilliseconds(
    data.updated_at ?? meta.updated_at,
  );
  const sampleSize = integer(data.sample_size_x_a, 0, 10_000_000);
  const referenceSampleSize = integer(
    data.sample_size_x_b,
    0,
    10_000_000,
  );
  const collectionProgress = rate(data.sample_collection_progress);

  const characters = normalizeCharacters(data.character);
  const teams = normalizeTeams(data.party);
  if (characters.length === 0 && teams.length === 0) {
    throw new AbyssStatisticsError("noData");
  }

  return {
    version: {
      scheduleId,
      periodStart: new Date(periodStart * 1_000).toISOString(),
      periodEnd: new Date(periodEnd * 1_000).toISOString(),
      sourceApiVersion,
    },
    metadata: {
      source: "AZA.GG",
      sourceUpdatedAt: new Date(sourceUpdatedAt).toISOString(),
      sampleSize,
      referenceSampleSize,
      collectionProgress,
    },
    characters,
    teams,
  };
}

function normalizeCharacters(value: unknown): AbyssCharacterStatistic[] {
  const source = object(value);
  const entries = Object.entries(source);
  if (entries.length > CHARACTER_LIMIT) invalid();

  return entries
    .map(([characterId, raw]) => {
      if (!CHARACTER_ID.test(characterId)) invalid();
      const item = object(raw);
      const { upperHalfRate, lowerHalfRate } = normalizePhaseRates(item.phase);
      return {
        characterId,
        usageRate: rate(item.use_rate),
        ownershipRate: rate(item.own_rate),
        usageAmongOwnersRate: rate(item.use_by_own_rate),
        upperHalfRate,
        lowerHalfRate,
        constellationRates: normalizeConstellations(item.constellations),
        weapons: normalizeRateList(item.weapons, EQUIPMENT_LIMIT),
        artifacts: normalizeArtifacts(item.artifacts),
      };
    })
    .sort((left, right) => right.usageRate - left.usageRate);
}

function normalizeConstellations(
  value: unknown,
): AbyssConstellationStatistic[] {
  if (value === undefined || value === null) return [];
  const source = array(value, 7);
  const seen = new Set<number>();
  const result = source.map((raw) => {
    const item = object(raw);
    const constellation = integer(item.id, 0, 6);
    if (seen.has(constellation)) invalid();
    seen.add(constellation);
    return { constellation, rate: rate(item.value) };
  });
  return result.sort((left, right) => left.constellation - right.constellation);
}

function normalizeRateList(
  value: unknown,
  limit: number,
): AbyssRateStatistic[] {
  if (value === undefined || value === null) return [];
  return array(value, limit)
    .map((raw) => {
      const item = object(raw);
      return {
        id: string(item.id, EQUIPMENT_ID),
        usageRate: rate(item.value),
      };
    })
    .sort((left, right) => right.usageRate - left.usageRate);
}

function normalizeArtifacts(value: unknown): AbyssArtifactStatistic[] {
  if (value === undefined || value === null) return [];
  const source = Array.isArray(value) ? value : [value];
  if (source.length > ARTIFACT_LIMIT) invalid();
  return source
    .map((raw) => {
      const item = object(raw);
      const set = object(item.set);
      const setPieces = Object.entries(set).map(([artifactSetId, pieces]) => {
        if (!EQUIPMENT_ID.test(artifactSetId)) invalid();
        return {
          artifactSetId,
          pieces: integer(pieces, 1, 5),
        };
      });
      if (setPieces.length > 2) invalid();
      return { setPieces, usageRate: rate(item.value) };
    })
    .sort((left, right) => right.usageRate - left.usageRate);
}

function normalizeTeams(value: unknown): AbyssTeamStatistic[] {
  const party = object(value);
  return [
    ...normalizeTeamHalf(party["1"], "upper"),
    ...normalizeTeamHalf(party["2"], "lower"),
  ];
}

function normalizeTeamHalf(
  value: unknown,
  half: "upper" | "lower",
): AbyssTeamStatistic[] {
  if (value === undefined || value === null) return [];
  const source = array(value, INPUT_TEAM_LIMIT_PER_HALF);
  const result: AbyssTeamStatistic[] = [];
  for (const raw of source) {
    const item = object(raw);
    const members = string(item.id, /^\d+(?:,\d+){0,7}$/).split(",");
    if (
      members.length !== 4 ||
      new Set(members).size !== 4 ||
      members.some((id) => !CHARACTER_ID.test(id))
    ) {
      continue;
    }
    result.push({
      half,
      members,
      usageRate: rate(item.use_rate),
      ownershipRate: rate(item.own_rate),
      usageAmongOwnersRate: rate(item.use_by_own_rate),
    });
  }
  return result
    .sort((left, right) => right.usageRate - left.usageRate)
    .slice(0, TEAM_LIMIT_PER_HALF);
}

function normalizePhaseRates(value: unknown): {
  upperHalfRate: number | null;
  lowerHalfRate: number | null;
} {
  if (value === undefined || value === null) {
    return { upperHalfRate: null, lowerHalfRate: null };
  }
  const phase = object(value);
  const upperHalfRate = optionalRate(phase["1"]);
  const explicitLowerHalfRate = optionalRate(phase["2"]);
  const hasExplicitLowerHalfRate = phase["2"] !== undefined;

  // 2026-07-19の実レスポンスは全120キャラでキー"1"のみ。
  // 明示的な"2"がない場合に限り、AZA.GG画面と同じ補数を下半比率として使う。
  const lowerHalfRate = hasExplicitLowerHalfRate
    ? explicitLowerHalfRate
    : upperHalfRate === null
    ? null
    : clampRate(1 - upperHalfRate);
  return { upperHalfRate, lowerHalfRate };
}

function optionalRate(value: unknown): number | null {
  return value === undefined || value === null ? null : rate(value);
}

function unixSeconds(value: unknown): number {
  const parsed = typeof value === "string" ? Number(value) : value;
  return integer(parsed, 946_684_800, 7_258_118_400);
}

function epochMilliseconds(value: unknown): number {
  return integer(value, 946_684_800_000, 7_258_118_400_000);
}

function rate(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) invalid();
  if (value < 0 || value > 1) invalid();
  return value;
}

function clampRate(value: number): number {
  return Math.max(0, Math.min(1, Number(value.toFixed(6))));
}

function integer(value: unknown, min: number, max: number): number {
  const parsed = typeof value === "string" && /^\d+$/.test(value)
    ? Number(value)
    : value;
  if (
    typeof parsed !== "number" ||
    !Number.isSafeInteger(parsed) ||
    parsed < min ||
    parsed > max
  ) {
    invalid();
  }
  return parsed;
}

function string(value: unknown, pattern: RegExp): string {
  if (typeof value !== "string" || !pattern.test(value)) invalid();
  return value;
}

function array(value: unknown, maxLength: number): unknown[] {
  if (!Array.isArray(value) || value.length > maxLength) invalid();
  return value;
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    invalid();
  }
  return value as Record<string, unknown>;
}

function invalid(): never {
  throw new AbyssStatisticsError("invalidResponse");
}
