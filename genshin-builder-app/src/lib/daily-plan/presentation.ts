import type {
  DailyPlanProposal,
  DailyPlanRecommendation,
  DailyPlanRecommendationSource,
} from "./types";

export interface DailyPlanTaskLabel {
  taskId: string;
  title: string;
}

export interface DailyPlanDisplayTask {
  title: string;
  reason: string;
  suggestedMinutes: number;
}

export interface DailyPlanDisplayModel {
  summary: string;
  primaryTask: DailyPlanDisplayTask;
  secondaryTasks: DailyPlanDisplayTask[];
  remainingTasks: DailyPlanDisplayTask[];
  deferredTasks: string[];
  warnings: string[];
  sourceLabel: string;
  generatedAtLabel: string;
  proposalFingerprint: string;
}

function sourceLabel(source: DailyPlanRecommendationSource): string {
  return source === "deepseek"
    ? "AIによる並び替え"
    : "通常ルールによる提案";
}

function toDisplayTask(
  recommendation: DailyPlanRecommendation,
  titles: Map<string, string>,
): DailyPlanDisplayTask | null {
  const title = titles.get(recommendation.taskId)?.trim();
  if (!title) return null;
  return {
    title,
    reason: recommendation.reason,
    suggestedMinutes: recommendation.suggestedMinutes,
  };
}

export function buildDailyPlanDisplayModel(
  proposal: DailyPlanProposal,
  taskLabels: DailyPlanTaskLabel[],
): DailyPlanDisplayModel | null {
  const titles = new Map(taskLabels.map((task) => [task.taskId, task.title]));
  const recommendations = [...proposal.recommendations]
    .sort((a, b) => a.priority - b.priority)
    .map((item) => toDisplayTask(item, titles));
  if (recommendations.length === 0 || recommendations.some((item) => item === null)) {
    return null;
  }

  const deferredTasks = proposal.deferredTaskIds.map((taskId) => titles.get(taskId)?.trim());
  if (deferredTasks.some((title) => !title)) return null;

  const [primaryTask, ...rest] = recommendations as DailyPlanDisplayTask[];
  return {
    summary: proposal.summary,
    primaryTask,
    secondaryTasks: rest.slice(0, 2),
    remainingTasks: rest.slice(2),
    deferredTasks: deferredTasks as string[],
    warnings: proposal.warnings,
    sourceLabel: sourceLabel(proposal.source),
    generatedAtLabel: new Intl.DateTimeFormat("ja-JP", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(proposal.generatedAt)),
    proposalFingerprint: proposal.proposalFingerprint,
  };
}
