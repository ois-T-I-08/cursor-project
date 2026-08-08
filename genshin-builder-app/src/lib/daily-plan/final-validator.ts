import type {
  DailyPlanAiResult,
  DailyPlanCandidate,
  DailyPlanEnrichRequest,
  DailyPlanProposal,
  DailyPlanRecommendation,
} from "./types";
import { DAILY_PLAN_SCHEMA_VERSION } from "./versions";

const MAX_RECOMMENDATIONS = 5;
const DEFAULT_MINUTES = 20;
const FORBIDDEN_FORMAT = /(?:https?:\/\/|www\.|<[^>]*>|\[[^\]]+\]\([^)]*\)|[*_`#])/i;

interface RankedCandidate {
  candidate: DailyPlanCandidate;
  score: number;
  ai?: DailyPlanRecommendation;
}

export function buildDeterministicDailyPlanProposal(
  request: DailyPlanEnrichRequest,
  inputHash: string,
  generatedAt = new Date(),
  safeErrorCode?: string,
): DailyPlanProposal {
  const ranked = request.candidates
    .map((candidate) => ({ candidate, score: deterministicScore(candidate) }))
    .sort(compareRanked);
  const finalized = selectWithinBudgets(request, ranked);
  const warnings = deterministicWarnings(request, safeErrorCode);
  return {
    schemaVersion: DAILY_PLAN_SCHEMA_VERSION,
    summary:
      finalized.recommendations.length > 0
        ? "今日実行できる候補を、入手日・目標差・既存優先度から並べました"
        : "今日実行できる候補を確認できませんでした",
    recommendations: finalized.recommendations,
    deferredTaskIds: finalized.deferredTaskIds,
    warnings,
    source: "deterministic_fallback",
    generatedAt: generatedAt.toISOString(),
    inputHash,
    proposalFingerprint: request.proposalFingerprint,
  };
}

export function validateAndFinalizeDailyPlan(
  raw: DailyPlanAiResult,
  request: DailyPlanEnrichRequest,
  inputHash: string,
  modelIdentifier: string,
  generatedAt = new Date(),
): DailyPlanProposal {
  const allowed = new Map(
    request.candidates.map((candidate) => [candidate.taskId, candidate]),
  );
  const seen = new Set<string>();
  const ranked: RankedCandidate[] = [];

  for (const recommendation of raw.recommendations) {
    const candidate = allowed.get(recommendation.taskId);
    if (!candidate || seen.has(candidate.taskId)) continue;
    seen.add(candidate.taskId);
    ranked.push({
      candidate,
      score:
        deterministicScore(candidate) +
        (MAX_RECOMMENDATIONS + 1 - recommendation.priority) * 4,
      ai: recommendation,
    });
  }

  ranked.sort(compareRanked);
  const fill = request.candidates
    .filter((candidate) => !seen.has(candidate.taskId))
    .map((candidate) => ({ candidate, score: deterministicScore(candidate) }))
    .sort(compareRanked);
  ranked.push(...fill);

  const finalized = selectWithinBudgets(request, ranked);
  const rawDeferred = new Set(
    raw.deferredTaskIds.filter((taskId) => allowed.has(taskId)),
  );
  for (const taskId of finalized.deferredTaskIds) rawDeferred.add(taskId);
  for (const recommendation of finalized.recommendations) {
    rawDeferred.delete(recommendation.taskId);
  }

  return {
    schemaVersion: DAILY_PLAN_SCHEMA_VERSION,
    summary: sanitizeSummary(raw.summary),
    recommendations: finalized.recommendations,
    deferredTaskIds: [...rawDeferred],
    warnings: [
      ...raw.warnings
        .map(sanitizeText)
        .filter((value): value is string => value !== null),
      ...deterministicWarnings(request),
    ]
      .filter((warning, index, all) => all.indexOf(warning) === index)
      .slice(0, 5),
    source: "deepseek",
    generatedAt: generatedAt.toISOString(),
    inputHash,
    proposalFingerprint: request.proposalFingerprint,
    modelIdentifier,
  };
}

function selectWithinBudgets(
  request: DailyPlanEnrichRequest,
  ranked: RankedCandidate[],
): {
  recommendations: DailyPlanRecommendation[];
  deferredTaskIds: string[];
} {
  const recommendations: DailyPlanRecommendation[] = [];
  const selected = new Set<string>();
  let remainingResin = request.currentResin ?? null;
  let remainingMinutes = request.availableMinutes ?? null;

  for (const entry of ranked) {
    if (recommendations.length >= MAX_RECOMMENDATIONS) break;
    const candidate = entry.candidate;
    if (selected.has(candidate.taskId) || !candidate.availableToday) continue;
    if (candidate.requiresResin && remainingResin === 0) continue;
    const resinCost = candidate.estimatedResinCost ?? null;
    if (remainingResin != null && resinCost != null && resinCost > remainingResin) {
      continue;
    }
    const minutes = normalizedMinutes(entry.ai?.suggestedMinutes, candidate);
    if (remainingMinutes != null && minutes > remainingMinutes) continue;

    selected.add(candidate.taskId);
    if (remainingResin != null && resinCost != null) remainingResin -= resinCost;
    if (remainingMinutes != null) remainingMinutes -= minutes;
    recommendations.push({
      taskId: candidate.taskId,
      priority: recommendations.length + 1,
      category: "do_today",
      reason: safeReason(entry.ai?.reason, candidate),
      suggestedMinutes: minutes,
    });
  }

  return {
    recommendations,
    deferredTaskIds: request.candidates
      .map((candidate) => candidate.taskId)
      .filter((taskId) => !selected.has(taskId)),
  };
}

function deterministicScore(candidate: DailyPlanCandidate): number {
  let score = candidate.existingPriority;
  if (!candidate.availableToday) return score - 1000;
  if (candidate.type === "weekdayMaterial") score += 90;
  if (candidate.type === "weeklyBoss") score += 55;
  if (candidate.bookmarked) score += 25;
  if (
    candidate.currentLevel != null &&
    candidate.targetLevel != null &&
    candidate.targetLevel > candidate.currentLevel
  ) {
    score += Math.min(40, candidate.targetLevel - candidate.currentLevel);
  }
  return score;
}

function compareRanked(a: RankedCandidate, b: RankedCandidate): number {
  return b.score - a.score || a.candidate.taskId.localeCompare(b.candidate.taskId);
}

function normalizedMinutes(
  suggested: number | undefined,
  candidate: DailyPlanCandidate,
): number {
  const upper = candidate.estimatedMinutes ?? 180;
  return Math.min(upper, Math.max(5, suggested ?? candidate.estimatedMinutes ?? DEFAULT_MINUTES));
}

function safeReason(
  aiReason: string | undefined,
  candidate: DailyPlanCandidate,
): string {
  const cleaned = aiReason == null ? null : sanitizeText(aiReason);
  if (cleaned != null) return cleaned;
  for (const fact of candidate.reasonFacts) {
    const safe = sanitizeText(fact);
    if (safe != null) return safe;
  }
  if (candidate.availableToday) return "今日実行でき、既存の優先度が高いため";
  return "既存の優先度に基づく候補です";
}

function sanitizeSummary(value: string): string {
  return sanitizeText(value) ?? "今日の候補を既存データから選びました";
}

function sanitizeText(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 120 || FORBIDDEN_FORMAT.test(trimmed)) {
    return null;
  }
  return trimmed;
}

function deterministicWarnings(
  request: DailyPlanEnrichRequest,
  safeErrorCode?: string,
): string[] {
  const warnings: string[] = [];
  if (request.currentResin == null) {
    warnings.push("樹脂残量を取得できないため、樹脂予算は最終確認してください");
  }
  if (request.availableMinutes == null) {
    warnings.push("利用可能時間が未設定のため、所要時間は目安です");
  }
  if (safeErrorCode && safeErrorCode !== "dailyPlanDisabled") {
    warnings.push("AI提案を利用できなかったため、通常ルールで提案しました");
  }
  return warnings.slice(0, 5);
}
