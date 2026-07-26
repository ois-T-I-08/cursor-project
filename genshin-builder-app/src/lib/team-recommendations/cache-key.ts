import { createHash } from "node:crypto";
import type { TeamRecommendationRequest } from "./types";

export function stableHash(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function teamRecommendationRequestHash(request: TeamRecommendationRequest): string {
  return stableHash({
    ...request,
    characters: [...request.characters].sort((a, b) => a.characterId.localeCompare(b.characterId)),
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
