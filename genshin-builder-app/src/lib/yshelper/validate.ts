import type {
  BattleValidationIssue,
  BattleValidationResult,
  NormalizedBattleStats,
} from "./types";

const UNKNOWN_RATIO_SUSPICIOUS = 0.05;
const RECORD_DROP_SUSPICIOUS = 0.5;
const RATE_SHIFT_SUSPICIOUS = 0.5;

export function validateBattleStats(
  value: NormalizedBattleStats,
  knownCharacterIds: ReadonlySet<string>,
  previous?: NormalizedBattleStats | null,
): BattleValidationResult {
  const issues: BattleValidationIssue[] = [];
  const teams = value.teams.map((team) => {
    const unknown = team.members.filter((id) => !knownCharacterIds.has(id));
    if (unknown.length > 0) {
      issues.push({
        code: "unknown_character",
        field: "teams.members",
        count: unknown.length,
      });
    }
    return { ...team, isResolved: unknown.length === 0 };
  });
  const characters = value.characters.map((character) => {
    const isResolved = knownCharacterIds.has(character.characterId);
    if (!isResolved) {
      issues.push({
        code: "unknown_character",
        field: "characters.characterId",
        count: 1,
      });
    }
    return { ...character, isResolved };
  });
  const next = { ...value, teams, characters };

  const recordCount = teams.length + characters.length;
  if (recordCount === 0) {
    issues.push({ code: "empty_payload", field: "$", count: 0 });
    return { state: "invalid", issues, value: next };
  }

  const unresolvedCount =
    teams.filter((item) => !item.isResolved).length +
    characters.filter((item) => !item.isResolved).length;
  if (unresolvedCount / recordCount > UNKNOWN_RATIO_SUSPICIOUS) {
    issues.push({
      code: "unknown_character_ratio",
      field: "$",
      count: unresolvedCount,
    });
  }

  if (previous) {
    const previousCount = previous.teams.length + previous.characters.length;
    if (
      previousCount > 0 &&
      recordCount / previousCount < RECORD_DROP_SUSPICIOUS
    ) {
      issues.push({
        code: "record_count_drop",
        field: "$",
        count: recordCount,
      });
    }
    if (hasSuspiciousRateShift(previous, next)) {
      issues.push({ code: "usage_rate_shift", field: "usageRate" });
    }
  }

  const suspicious = issues.some(
    (issue) =>
      issue.code === "unknown_character_ratio" ||
      issue.code === "record_count_drop" ||
      issue.code === "usage_rate_shift",
  );
  return { state: suspicious ? "suspicious" : "valid", issues, value: next };
}

export function publishableBattleStats(
  value: NormalizedBattleStats,
): NormalizedBattleStats {
  return {
    ...value,
    metadata: {},
    teams: value.teams
      .filter((item) => item.isResolved)
      .map((item) => ({ ...item, sourceMetadata: {} })),
    characters: value.characters.filter((item) => item.isResolved),
  };
}

function hasSuspiciousRateShift(
  previous: NormalizedBattleStats,
  current: NormalizedBattleStats,
): boolean {
  const previousTeams = new Map(
    previous.teams.map((team) => [
      `${team.teamKey}|${team.side ?? ""}|${team.stageKey ?? ""}`,
      team.usageRate,
    ]),
  );
  for (const team of current.teams) {
    const before = previousTeams.get(
      `${team.teamKey}|${team.side ?? ""}|${team.stageKey ?? ""}`,
    );
    if (before !== undefined && Math.abs(team.usageRate - before) > RATE_SHIFT_SUSPICIOUS) {
      return true;
    }
  }
  const previousCharacters = new Map(
    previous.characters.map((character) => [
      `${character.characterId}|${character.side ?? ""}`,
      character.usageRate,
    ]),
  );
  return current.characters.some((character) => {
    const before = previousCharacters.get(
      `${character.characterId}|${character.side ?? ""}`,
    );
    return before !== undefined &&
      Math.abs(character.usageRate - before) > RATE_SHIFT_SUSPICIOUS;
  });
}
