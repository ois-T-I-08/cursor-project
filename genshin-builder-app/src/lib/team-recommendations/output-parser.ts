import type { GcsimRunResult } from "./types";
import { GCSIM_COMMIT_SHA, GCSIM_RESULT_SCHEMA_VERSION } from "./settings";

export class GcsimOutputParser {
  parse(raw: string): GcsimRunResult {
    let value: unknown;
    try { value = JSON.parse(raw); } catch { throw new Error("invalidGcsimOutput"); }
    if (!isRecord(value) || !isRecord(value.schema_version) || !isRecord(value.statistics)) throw new Error("invalidGcsimOutput");
    if (`${value.schema_version.major}.${value.schema_version.minor}` !== GCSIM_RESULT_SCHEMA_VERSION) throw new Error("invalidGcsimOutput");
    if (value.sim_version !== GCSIM_COMMIT_SHA) throw new Error("invalidGcsimOutput");
    const statistics = value.statistics;
    if (!isRecord(statistics.dps) || !finiteNonNegative(statistics.dps.mean) || !integer(statistics.iterations, 1, 100_000)) {
      throw new Error("invalidGcsimOutput");
    }
    const reactions: Record<string, number> = {};
    if (Array.isArray(statistics.source_reactions)) {
      for (const entry of statistics.source_reactions) {
        if (!isRecord(entry) || !isRecord(entry.sources)) continue;
        for (const [key, stat] of Object.entries(entry.sources)) {
          if (isRecord(stat) && finiteNonNegative(stat.mean)) reactions[key] = (reactions[key] ?? 0) + stat.mean;
        }
      }
    }
    const endingEnergy = Array.isArray(statistics.end_stats)
      ? statistics.end_stats.map((entry) => isRecord(entry) && isRecord(entry.ending_energy) && finiteNonNegative(entry.ending_energy.mean) ? entry.ending_energy.mean : 0)
      : [];
    return { estimatedDps: statistics.dps.mean, iterations: statistics.iterations, reactions, endingEnergy };
  }
}

function finiteNonNegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}
function integer(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= min && value <= max;
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
