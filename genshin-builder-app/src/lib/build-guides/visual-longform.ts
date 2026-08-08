import "server-only";

import {
  estimateVisualPromptTokens,
  VISUAL_PROMPT_TOKEN_HARD_MAX,
  VISUAL_TOKENS_PER_SECOND_AT_1FPS,
} from "./visual-analysis-safety";
import {
  videoVisualAnalysisResultSchema,
  type VideoVisualAnalysisResult,
} from "./visual-schemas";

/** Bump when chunk boundary policy changes (affects identity / cache). */
export const LONGFORM_CHUNK_VERSION = "v1";

/** Per-chunk token target — headroom under hard max. */
export const LONGFORM_CHUNK_TOKEN_TARGET = 45_000;

/** Boundary overlap (seconds) — small, merge-deduplicated. */
export const LONGFORM_OVERLAP_SECONDS = 12;

/** Reject runaway plans before any provider call. */
export const LONGFORM_MAX_CHUNKS = 40;

/** Soft cap on estimated provider HTTP calls (1 call / chunk). */
export const LONGFORM_MAX_AI_CALLS = 40;

/** Merge payload token estimate soft limit before hierarchical reduce. */
export const LONGFORM_MERGE_TOKEN_SOFT_MAX = 40_000;

export type LongformChunkPlan = {
  chunkIndex: number;
  startSeconds: number;
  endSeconds: number;
  reason: string;
  estimatedTokens: number;
  /** Stable identity fragment for cache / resume. */
  chunkKey: string;
};

export type LongformPlan = {
  version: typeof LONGFORM_CHUNK_VERSION;
  durationSeconds: number;
  fps: number;
  chunkSeconds: number;
  overlapSeconds: number;
  chunks: LongformChunkPlan[];
  estimatedInputTokens: number;
  estimatedAiCalls: number;
};

export class LongformPlanningError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "LongformPlanningError";
  }
}

export function computeLongformChunkSeconds(input: {
  fps: number;
  targetCharacterCount: number;
  tokenTarget?: number;
  maxRangeSeconds: number;
}): number {
  const fps = Math.max(0.1, input.fps);
  const tokenTarget = input.tokenTarget ?? LONGFORM_CHUNK_TOKEN_TARGET;
  const overhead = 2_000 + Math.max(0, input.targetCharacterCount) * 8;
  const mediaBudget = Math.max(1_000, tokenTarget - overhead);
  const byTokens = Math.floor(
    mediaBudget / (fps * VISUAL_TOKENS_PER_SECOND_AT_1FPS),
  );
  const capped = Math.min(input.maxRangeSeconds, Math.max(30, byTokens));
  // Keep well under hard max even if settings drift.
  const hardSeconds = Math.floor(
    (VISUAL_PROMPT_TOKEN_HARD_MAX - overhead) /
      (fps * VISUAL_TOKENS_PER_SECOND_AT_1FPS),
  );
  return Math.min(capped, Math.max(30, hardSeconds - 30));
}

export function planLongformChunks(input: {
  videoId: string;
  durationSeconds: number;
  fps: number;
  targetCharacterCount: number;
  maxRangeSeconds: number;
  overlapSeconds?: number;
  /** Optional semantic / transcript cut points (seconds). */
  boundaryHints?: number[];
}): LongformPlan {
  const duration = Math.max(1, Math.floor(input.durationSeconds));
  const fps = Math.max(0.1, input.fps);
  const overlap = Math.max(
    0,
    Math.min(30, input.overlapSeconds ?? LONGFORM_OVERLAP_SECONDS),
  );
  const chunkSeconds = computeLongformChunkSeconds({
    fps,
    targetCharacterCount: input.targetCharacterCount,
    maxRangeSeconds: input.maxRangeSeconds,
  });
  const step = Math.max(15, chunkSeconds - overlap);

  const hints = (input.boundaryHints ?? [])
    .filter((s) => Number.isFinite(s) && s > 0 && s < duration)
    .map((s) => Math.floor(s))
    .sort((a, b) => a - b);

  const chunks: LongformChunkPlan[] = [];
  let cursor = 0;
  while (cursor < duration) {
    let end = Math.min(duration, cursor + chunkSeconds);
    // Snap end to nearby semantic hint when within 20s (avoid tiny leftovers).
    for (const hint of hints) {
      if (hint > cursor + 30 && hint < end + 20 && hint <= duration) {
        end = Math.min(duration, Math.max(end, hint));
        break;
      }
    }
    if (end <= cursor) break;
    const estimatedTokens = estimateVisualPromptTokens({
      durationSeconds: duration,
      fps,
      analysisMode: "clipped_detail",
      rangeSecondsTotal: end - cursor,
      targetCharacterCount: input.targetCharacterCount,
    });
    if (estimatedTokens > VISUAL_PROMPT_TOKEN_HARD_MAX) {
      throw new LongformPlanningError("longformChunkExceedsHardMax");
    }
    const chunkIndex = chunks.length;
    chunks.push({
      chunkIndex,
      startSeconds: cursor,
      endSeconds: end,
      reason: `longform:${LONGFORM_CHUNK_VERSION}:chunk:${chunkIndex}`,
      estimatedTokens,
      chunkKey: buildLongformChunkKey({
        videoId: input.videoId,
        chunkIndex,
        startSeconds: cursor,
        endSeconds: end,
        fps,
      }),
    });
    if (end >= duration) break;
    cursor = end - overlap;
    if (cursor <= chunks[chunks.length - 1]!.startSeconds) {
      cursor = end;
    }
  }

  const estimatedInputTokens = chunks.reduce(
    (sum, c) => sum + c.estimatedTokens,
    0,
  );
  const plan: LongformPlan = {
    version: LONGFORM_CHUNK_VERSION,
    durationSeconds: duration,
    fps,
    chunkSeconds,
    overlapSeconds: overlap,
    chunks,
    estimatedInputTokens,
    estimatedAiCalls: chunks.length,
  };
  assertLongformCostGuard(plan);
  return plan;
}

export function assertLongformCostGuard(plan: LongformPlan): void {
  if (plan.chunks.length === 0) {
    throw new LongformPlanningError("longformEmptyPlan");
  }
  if (plan.chunks.length > LONGFORM_MAX_CHUNKS) {
    throw new LongformPlanningError("longformTooManyChunks");
  }
  if (plan.estimatedAiCalls > LONGFORM_MAX_AI_CALLS) {
    throw new LongformPlanningError("longformTooManyAiCalls");
  }
}

export function buildLongformChunkKey(input: {
  videoId: string;
  chunkIndex: number;
  startSeconds: number;
  endSeconds: number;
  fps: number;
}): string {
  return [
    input.videoId,
    LONGFORM_CHUNK_VERSION,
    `c${input.chunkIndex}`,
    `${input.startSeconds}-${input.endSeconds}`,
    `fps${input.fps}`,
  ].join(":");
}

export function needsLongformFullDiscovery(input: {
  durationSeconds: number | null;
  fps: number;
  targetCharacterCount: number;
}): boolean {
  if (input.durationSeconds == null || input.durationSeconds <= 0) return false;
  const estimated = estimateVisualPromptTokens({
    durationSeconds: input.durationSeconds,
    fps: input.fps,
    analysisMode: "full_discovery",
    targetCharacterCount: input.targetCharacterCount,
  });
  return estimated > VISUAL_PROMPT_TOKEN_HARD_MAX;
}

/** Dedupe evidences across overlapping chunks; preserve conflicts. */
export function mergeLongformChunkResults(
  videoId: string,
  chunks: Array<{
    chunkIndex: number;
    result: VideoVisualAnalysisResult;
  }>,
): VideoVisualAnalysisResult {
  const ordered = [...chunks].sort((a, b) => a.chunkIndex - b.chunkIndex);
  const evidences = ordered.flatMap((c) =>
    c.result.evidences.map((e) => ({
      ...e,
      // Tag source segment without inventing schema fields — fold into notes/warnings.
      warnings: [
        ...(e.warnings ?? []),
        `source_chunk:${c.chunkIndex}`,
      ].slice(0, 20),
    })),
  );

  const deduped = dedupeEvidences(evidences);
  const unresolved = ordered.flatMap((c) => c.result.unresolvedEntities);
  const characters = [
    ...new Set(ordered.flatMap((c) => c.result.detectedCharacterIds)),
  ];

  return videoVisualAnalysisResultSchema.parse({
    videoId,
    relevant:
      ordered.some((c) => c.result.relevant) || deduped.length > 0,
    detectedCharacterIds: characters.slice(0, 40),
    evidences: deduped.slice(0, 80),
    unresolvedEntities: dedupeUnresolved(unresolved).slice(0, 40),
    analysisSummary: ordered
      .map((c) => c.result.analysisSummary)
      .filter(Boolean)
      .join(" | ")
      .slice(0, 1000),
  });
}

function evidenceContentKey(
  evidence: VideoVisualAnalysisResult["evidences"][number],
): string {
  // Timestamps omitted so overlap windows can consolidate the same reading.
  const texts = (evidence.visibleTexts ?? [])
    .map((t) => t.text.trim())
    .filter(Boolean)
    .join("|");
  const stats = (evidence.statValues ?? [])
    .map(
      (s) =>
        `${s.statKey}:${s.recommended ?? s.minimum ?? ""}:${s.unit ?? ""}:${s.purpose ?? ""}`,
    )
    .join("|");
  return [
    evidence.evidenceType,
    texts.slice(0, 160),
    stats.slice(0, 160),
    (evidence.targetCharacterIds ?? []).slice().sort().join(","),
    (evidence.statPriority ?? []).join(","),
  ].join("::");
}

function dedupeEvidences(
  evidences: VideoVisualAnalysisResult["evidences"],
): VideoVisualAnalysisResult["evidences"] {
  const byKey = new Map<string, VideoVisualAnalysisResult["evidences"][number]>();
  for (const evidence of evidences) {
    const key = evidenceContentKey(evidence);
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, evidence);
      continue;
    }
    // Widen time span; preserve higher confidence; union warnings.
    byKey.set(key, {
      ...existing,
      startSeconds: Math.min(existing.startSeconds, evidence.startSeconds),
      endSeconds: Math.max(existing.endSeconds, evidence.endSeconds),
      confidence: Math.max(existing.confidence, evidence.confidence),
      warnings: [
        ...new Set([...(existing.warnings ?? []), ...(evidence.warnings ?? [])]),
      ].slice(0, 20),
    });
  }
  return [...byKey.values()];
}

function dedupeUnresolved(
  items: VideoVisualAnalysisResult["unresolvedEntities"],
): VideoVisualAnalysisResult["unresolvedEntities"] {
  const seen = new Set<string>();
  const out: VideoVisualAnalysisResult["unresolvedEntities"] = [];
  for (const item of items) {
    const key = `${item.type}:${item.exactVisibleText}:${item.timestampSeconds}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

/**
 * Hierarchical reduce for merge token guard (structured, no giant prompt dump).
 * Groups chunk results, merges each group, then merges groups.
 */
export function reduceLongformChunkResults(
  videoId: string,
  chunks: Array<{ chunkIndex: number; result: VideoVisualAnalysisResult }>,
  groupSize = 4,
): {
  result: VideoVisualAnalysisResult;
  levels: number;
  estimatedMergeTokens: number;
} {
  if (chunks.length === 0) {
    throw new LongformPlanningError("longformEmptyMerge");
  }
  let level = 0;
  let current = [...chunks].sort((a, b) => a.chunkIndex - b.chunkIndex);
  let estimatedMergeTokens = estimateMergeTokens(current.map((c) => c.result));

  while (
    current.length > groupSize &&
    estimatedMergeTokens > LONGFORM_MERGE_TOKEN_SOFT_MAX
  ) {
    const next: typeof current = [];
    for (let i = 0; i < current.length; i += groupSize) {
      const group = current.slice(i, i + groupSize);
      const merged = mergeLongformChunkResults(videoId, group);
      next.push({ chunkIndex: i / groupSize, result: merged });
    }
    current = next;
    level += 1;
    estimatedMergeTokens = estimateMergeTokens(current.map((c) => c.result));
    if (level > 8) break;
  }

  const result = mergeLongformChunkResults(videoId, current);
  return {
    result,
    levels: level + 1,
    estimatedMergeTokens: estimateMergeTokens([result]),
  };
}

export function estimateMergeTokens(
  results: VideoVisualAnalysisResult[],
): number {
  // Rough structured size — never dump raw provider text into merge.
  let chars = 0;
  for (const r of results) {
    chars += (r.analysisSummary?.length ?? 0) + 64;
    for (const e of r.evidences) {
      chars += 80;
      for (const t of e.visibleTexts ?? []) chars += t.text.length;
      chars += (e.statValues?.length ?? 0) * 24;
      chars += (e.statPriority?.length ?? 0) * 12;
    }
  }
  return Math.ceil(chars / 4) + 500;
}

export type LongformPartialState = {
  status: "complete" | "partial" | "aborted_emergency" | "aborted_rate_limit";
  completedChunkIndexes: number[];
  failedChunkIndex: number | null;
  failedCode: string | null;
};

export function buildLongformPartialState(input: {
  plan: LongformPlan;
  completedChunkIndexes: number[];
  failedChunkIndex?: number | null;
  failedCode?: string | null;
  emergency?: boolean;
  rateLimited?: boolean;
}): LongformPartialState {
  const completed = [...new Set(input.completedChunkIndexes)].sort(
    (a, b) => a - b,
  );
  if (input.emergency) {
    return {
      status: "aborted_emergency",
      completedChunkIndexes: completed,
      failedChunkIndex: input.failedChunkIndex ?? null,
      failedCode: "emergencyStopped",
    };
  }
  if (input.rateLimited) {
    return {
      status: "aborted_rate_limit",
      completedChunkIndexes: completed,
      failedChunkIndex: input.failedChunkIndex ?? null,
      failedCode: input.failedCode ?? "http429",
    };
  }
  if (
    completed.length === input.plan.chunks.length &&
    input.failedChunkIndex == null
  ) {
    return {
      status: "complete",
      completedChunkIndexes: completed,
      failedChunkIndex: null,
      failedCode: null,
    };
  }
  return {
    status: "partial",
    completedChunkIndexes: completed,
    failedChunkIndex: input.failedChunkIndex ?? null,
    failedCode: input.failedCode ?? "longformPartialFailure",
  };
}

/** Incomplete long-form must never be treated as publishable full discovery. */
export function isLongformPublishable(state: LongformPartialState): boolean {
  return state.status === "complete";
}

/**
 * Per-chunk provider usage for long-form observability.
 * Persisted under job.rangesPayload.chunkUsage (no schema migration).
 * Never store prompts, secrets, cookies, or API keys.
 * Never invent actual* from estimatedTokens / prior runs.
 */
export type LongformChunkUsageRecord = {
  chunkIndex: number;
  rangeStart: number;
  rangeEnd: number;
  estimatedTokens: number;
  actualPromptTokens: number | null;
  actualCandidateTokens: number | null;
  actualTotalTokens: number | null;
  attempts: number;
  retryCount: number;
  cacheHit: boolean;
  provider: string;
  requestHash: string;
};

function finiteNonNegInt(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const n = Math.trunc(value);
  return n >= 0 ? n : null;
}

/** Read provider usage counters only — never fall back to estimates. */
export function readActualTokenCountsFromUsage(
  usage: Record<string, number> | null | undefined,
): Pick<
  LongformChunkUsageRecord,
  "actualPromptTokens" | "actualCandidateTokens" | "actualTotalTokens"
> {
  if (!usage || typeof usage !== "object") {
    return {
      actualPromptTokens: null,
      actualCandidateTokens: null,
      actualTotalTokens: null,
    };
  }
  return {
    actualPromptTokens: finiteNonNegInt(usage.promptTokenCount),
    actualCandidateTokens: finiteNonNegInt(usage.candidatesTokenCount),
    actualTotalTokens: finiteNonNegInt(usage.totalTokenCount),
  };
}

export function buildLongformChunkUsageRecord(input: {
  chunkIndex: number;
  rangeStart: number;
  rangeEnd: number;
  estimatedTokens: number;
  usage?: Record<string, number> | null;
  attempts?: number;
  cacheHit: boolean;
  provider: string;
  requestHash: string;
}): LongformChunkUsageRecord {
  const cacheHit = Boolean(input.cacheHit);
  const attempts = cacheHit
    ? 0
    : Math.max(0, Math.trunc(input.attempts ?? 0));
  const tokens = cacheHit
    ? {
        actualPromptTokens: null,
        actualCandidateTokens: null,
        actualTotalTokens: null,
      }
    : readActualTokenCountsFromUsage(input.usage);
  return {
    chunkIndex: Math.max(0, Math.trunc(input.chunkIndex)),
    rangeStart: Math.max(0, Math.trunc(input.rangeStart)),
    rangeEnd: Math.max(0, Math.trunc(input.rangeEnd)),
    estimatedTokens: Math.max(0, Math.trunc(input.estimatedTokens)),
    ...tokens,
    attempts,
    retryCount: Math.max(0, attempts > 0 ? attempts - 1 : 0),
    cacheHit,
    provider: String(input.provider || "").slice(0, 80),
    requestHash: String(input.requestHash || "")
      .replace(/[^a-fA-F0-9]/g, "")
      .slice(0, 128),
  };
}

/** Parse chunkUsage from rangesPayload JSON (string or object). */
export function extractLongformChunkUsage(
  rangesPayload: string | Record<string, unknown> | null | undefined,
): LongformChunkUsageRecord[] {
  let root: Record<string, unknown> | null = null;
  if (typeof rangesPayload === "string") {
    try {
      root = JSON.parse(rangesPayload || "{}") as Record<string, unknown>;
    } catch {
      return [];
    }
  } else if (rangesPayload && typeof rangesPayload === "object") {
    root = rangesPayload;
  }
  if (!root) return [];

  const nested =
    root.longform && typeof root.longform === "object"
      ? (root.longform as Record<string, unknown>).chunkUsage
      : undefined;
  const raw = Array.isArray(root.chunkUsage)
    ? root.chunkUsage
    : Array.isArray(nested)
      ? nested
      : [];

  const out: LongformChunkUsageRecord[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const r = item as Record<string, unknown>;
    const cacheHit = r.cacheHit === true;
    const attempts = finiteNonNegInt(r.attempts) ?? 0;
    out.push({
      chunkIndex: finiteNonNegInt(r.chunkIndex) ?? 0,
      rangeStart: finiteNonNegInt(r.rangeStart) ?? 0,
      rangeEnd: finiteNonNegInt(r.rangeEnd) ?? 0,
      estimatedTokens: finiteNonNegInt(r.estimatedTokens) ?? 0,
      actualPromptTokens: cacheHit
        ? null
        : finiteNonNegInt(r.actualPromptTokens),
      actualCandidateTokens: cacheHit
        ? null
        : finiteNonNegInt(r.actualCandidateTokens),
      actualTotalTokens: cacheHit
        ? null
        : finiteNonNegInt(r.actualTotalTokens),
      attempts,
      retryCount:
        finiteNonNegInt(r.retryCount) ?? Math.max(0, attempts > 0 ? attempts - 1 : 0),
      cacheHit,
      provider: String(typeof r.provider === "string" ? r.provider : "").slice(
        0,
        80,
      ),
      requestHash: String(
        typeof r.requestHash === "string" ? r.requestHash : "",
      )
        .replace(/[^a-fA-F0-9]/g, "")
        .slice(0, 128),
    });
  }
  return out.sort((a, b) => a.chunkIndex - b.chunkIndex);
}
