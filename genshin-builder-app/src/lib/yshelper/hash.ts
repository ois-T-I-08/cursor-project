import { createHash } from "node:crypto";

import type { NormalizedBattleStats } from "./types";

export function hashBattleStats(value: NormalizedBattleStats): string {
  return `sha256:${createHash("sha256")
    .update(stableStringify(hashable(value)), "utf8")
    .digest("hex")}`;
}

export function stableStringify(value: unknown): string {
  if (value === undefined) return "null";
  if (value === null || typeof value !== "object") {
    if (typeof value === "number") {
      return JSON.stringify(Number(value.toFixed(8)));
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .filter((key) => record[key] !== undefined)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(",")}}`;
}

function hashable(value: NormalizedBattleStats): unknown {
  return {
    ...value,
    teams: [...value.teams]
      .map((team) => ({
        ...team,
        members: [...team.members].sort(),
      }))
      .sort((a, b) =>
        `${a.teamKey}|${a.side ?? ""}|${a.stageKey ?? ""}`.localeCompare(
          `${b.teamKey}|${b.side ?? ""}|${b.stageKey ?? ""}`,
        ),
      ),
    characters: [...value.characters].sort((a, b) =>
      `${a.characterId}|${a.side ?? ""}`.localeCompare(
        `${b.characterId}|${b.side ?? ""}`,
      ),
    ),
  };
}
