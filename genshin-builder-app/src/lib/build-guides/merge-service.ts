import type { ValidatedGuidePayload } from "./schemas";
import { guideStatKeySchema, type GuideStatKey } from "./schemas";

export interface MergeConflict {
  fieldPath: string;
  values: Array<{ videoId: string; value: unknown }>;
  severity: "warning" | "blocking";
}

export interface MergeCandidate {
  payload: ValidatedGuidePayload;
  conflicts: MergeConflict[];
  sourceVideoIds: string[];
}

function sameNumber(a: number | undefined, b: number | undefined): boolean {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return Math.abs(a - b) < 1e-6;
}

export function mergeGuidePayloads(
  characterId: string,
  sources: Array<{ videoId: string; payload: ValidatedGuidePayload }>,
): MergeCandidate {
  if (sources.length === 0) {
    throw new Error("noSources");
  }
  if (sources.length === 1) {
    return {
      payload: sources[0]!.payload,
      conflicts: [],
      sourceVideoIds: [sources[0]!.videoId],
    };
  }

  const conflicts: MergeConflict[] = [];
  const context = { ...sources[0]!.payload.context };
  for (const source of sources.slice(1)) {
    for (const key of ["role", "teamArchetype", "weaponPreference"] as const) {
      const a = context[key];
      const b = source.payload.context[key];
      if (a && b && a !== b) {
        conflicts.push({
          fieldPath: `context.${key}`,
          values: sources.map((s) => ({
            videoId: s.videoId,
            value: s.payload.context[key] ?? null,
          })),
          severity: "warning",
        });
      }
    }
  }

  const targetByStat = new Map<
    GuideStatKey,
    { recommended?: number; min?: number; max?: number; unit?: "flat" | "percent" }
  >();
  for (const source of sources) {
    for (const target of source.payload.targets) {
      const existing = targetByStat.get(target.stat);
      if (!existing) {
        targetByStat.set(target.stat, {
          recommended: target.recommended,
          min: target.min,
          max: target.max,
          unit: target.unit,
        });
        continue;
      }
      if (
        !sameNumber(existing.recommended, target.recommended) ||
        !sameNumber(existing.min, target.min) ||
        !sameNumber(existing.max, target.max)
      ) {
        conflicts.push({
          fieldPath: `targets.${target.stat}`,
          values: sources.flatMap((s) =>
            s.payload.targets
              .filter((t) => t.stat === target.stat)
              .map((t) => ({ videoId: s.videoId, value: t })),
          ),
          severity: "blocking",
        });
      }
      if (existing.min != null && target.min != null) {
        existing.min = Math.min(existing.min, target.min);
      } else {
        existing.min = existing.min ?? target.min;
      }
      if (existing.max != null && target.max != null) {
        existing.max = Math.max(existing.max, target.max);
      } else {
        existing.max = existing.max ?? target.max;
      }
      if (existing.recommended == null) existing.recommended = target.recommended;
    }
  }

  const priorityVotes = new Map<GuideStatKey, number>();
  for (const source of sources) {
    source.payload.substatPriority.forEach((stat, index) => {
      priorityVotes.set(stat, (priorityVotes.get(stat) ?? 0) + (10 - index));
    });
  }
  const substatPriority = [...priorityVotes.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([stat]) => guideStatKeySchema.parse(stat));

  const mainStats = sources[0]!.payload.mainStats;
  for (const source of sources.slice(1)) {
    for (const slot of source.payload.mainStats) {
      const match = mainStats.find((item) => item.slot === slot.slot);
      if (!match) {
        mainStats.push(slot);
        continue;
      }
      if (match.stats.join("|") !== slot.stats.join("|")) {
        conflicts.push({
          fieldPath: `mainStats.${slot.slot}`,
          values: sources.flatMap((s) =>
            s.payload.mainStats
              .filter((m) => m.slot === slot.slot)
              .map((m) => ({ videoId: s.videoId, value: m.stats })),
          ),
          severity: "warning",
        });
      }
    }
  }

  const overallConfidence =
    sources.reduce((sum, s) => sum + s.payload.overallConfidence, 0) / sources.length;

  const caveats = [
    ...new Set(sources.flatMap((s) => s.payload.caveats)),
    ...(conflicts.some((c) => c.severity === "blocking")
      ? ["複数動画間で数値推奨に矛盾があります。管理者確認が必要です。"]
      : []),
  ].slice(0, 10);

  return {
    payload: {
      characterId,
      context,
      mainStats,
      substatPriority,
      targets: [...targetByStat.entries()].map(([stat, value]) => ({
        stat,
        ...value,
        inferred: false,
      })),
      overallConfidence,
      caveats,
      unresolvedEntities: [
        ...new Set(sources.flatMap((s) => s.payload.unresolvedEntities)),
      ].slice(0, 20),
    },
    conflicts,
    sourceVideoIds: sources.map((s) => s.videoId),
  };
}
