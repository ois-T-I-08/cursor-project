export const DAILY_PLAN_ITEM_TYPES = [
  "weekdayMaterial",
  "weeklyBoss",
  "characterLevel",
  "characterAscension",
  "talent",
  "weapon",
  "growthGoal",
  "generalMaterial",
] as const;

export type DailyPlanItemType = (typeof DAILY_PLAN_ITEM_TYPES)[number];

export interface DailyPlanCandidate {
  taskId: string;
  type: DailyPlanItemType;
  title: string;
  characterIds: string[];
  materialIds: string[];
  currentLevel?: number | null;
  targetLevel?: number | null;
  estimatedResinCost?: number | null;
  estimatedMinutes?: number | null;
  availableToday: boolean;
  requiresResin: boolean;
  bookmarked: boolean;
  existingPriority: number;
  reasonFacts: string[];
}

export interface DailyPlanEnrichRequest {
  clientScope: string;
  date: string;
  timezone: string;
  weekday: number;
  currentResin?: number | null;
  maxResin?: number | null;
  availableMinutes?: number | null;
  force?: boolean;
  candidates: DailyPlanCandidate[];
}

export type DailyPlanRecommendationSource =
  | "deepseek"
  | "deterministic_fallback";

export interface DailyPlanRecommendation {
  taskId: string;
  priority: number;
  category: "do_today";
  reason: string;
  suggestedMinutes: number;
}

export interface DailyPlanProposal {
  summary: string;
  recommendations: DailyPlanRecommendation[];
  deferredTaskIds: string[];
  warnings: string[];
  source: DailyPlanRecommendationSource;
  generatedAt: string;
  inputHash: string;
  modelIdentifier?: string;
}

export interface DailyPlanAiResult {
  summary: string;
  recommendations: DailyPlanRecommendation[];
  deferredTaskIds: string[];
  warnings: string[];
}

export interface DailyPlanCacheIdentity {
  clientScope: string;
  date: string;
  timezone: string;
  candidateHash: string;
  progressHash: string;
  resinState: string;
  promptVersion: string;
  rulesVersion: string;
  modelIdentifier: string;
}

export interface DailyPlanGenerationMetadata {
  inputHash: string;
  candidateCount: number;
  modelIdentifier: string;
  attempts: number;
  usage: Record<string, number>;
  safeErrorCode?: string;
  generatedAt: string;
  source: DailyPlanRecommendationSource;
}
