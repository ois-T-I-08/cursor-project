import { createHash } from "node:crypto";
import {
  GCSIM_COMMIT_SHA,
  GCSIM_CONFIG_SCHEMA_VERSION,
  GCSIM_RESULT_SCHEMA_VERSION,
  GCSIM_VERSION,
  ROTATION_TEMPLATE_VERSION,
} from "./settings";
import type { TeamCandidate, TeamRecommendationRequest } from "./types";

export function stableHash(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function teamRecommendationRequestHash(request: TeamRecommendationRequest): string {
  return stableHash({
    ...request,
    characters: [...request.characters].sort((a, b) => a.characterId.localeCompare(b.characterId)),
  });
}

export function simulationCacheKey(input: {
  request: TeamRecommendationRequest;
  candidate: TeamCandidate;
  iterations: number;
  durationSeconds: number;
}): string {
  return stableHash({
    gcsimVersion: GCSIM_VERSION,
    gcsimCommitSha: GCSIM_COMMIT_SHA,
    configSchemaVersion: GCSIM_CONFIG_SCHEMA_VERSION,
    resultSchemaVersion: GCSIM_RESULT_SCHEMA_VERSION,
    attackerId: input.request.attackerId,
    teamCharacterIds: [input.request.attackerId, ...input.candidate.members.filter((id) => id !== input.request.attackerId).sort()],
    normalizedBuildHash: stableHash(input.request.characters
      .filter((build) => input.candidate.members.includes(build.characterId))
      .sort((a, b) => a.characterId.localeCompare(b.characterId))),
    enemyConfigHash: stableHash({ enemy: input.request.enemy, mode: input.request.mode, half: input.request.half }),
    rotationTemplateVersion: ROTATION_TEMPLATE_VERSION,
    iterations: input.iterations,
    durationSeconds: input.durationSeconds,
  });
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
