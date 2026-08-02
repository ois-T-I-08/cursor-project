import "server-only";

import { createHash } from "node:crypto";

import type {
  DailyPlanCacheIdentity,
  DailyPlanEnrichRequest,
} from "./types";
import {
  DAILY_PLAN_PROMPT_VERSION,
  DAILY_PLAN_RULES_VERSION,
} from "./versions";

export function dailyPlanCacheIdentity(
  request: DailyPlanEnrichRequest,
  modelIdentifier: string,
): DailyPlanCacheIdentity {
  const candidates = [...request.candidates]
    .sort((a, b) => a.taskId.localeCompare(b.taskId))
    .map((candidate) => ({
      taskId: candidate.taskId,
      type: candidate.type,
      title: candidate.title,
      characterIds: [...candidate.characterIds].sort(),
      materialIds: [...candidate.materialIds].sort(),
      availableToday: candidate.availableToday,
      requiresResin: candidate.requiresResin,
      bookmarked: candidate.bookmarked,
      reasonFacts: [...candidate.reasonFacts],
    }));
  const progress = [...request.candidates]
    .sort((a, b) => a.taskId.localeCompare(b.taskId))
    .map((candidate) => ({
      taskId: candidate.taskId,
      currentLevel: candidate.currentLevel ?? null,
      targetLevel: candidate.targetLevel ?? null,
      estimatedResinCost: candidate.estimatedResinCost ?? null,
      estimatedMinutes: candidate.estimatedMinutes ?? null,
      existingPriority: candidate.existingPriority,
    }));

  return {
    clientScope: request.clientScope,
    date: request.date,
    timezone: request.timezone,
    candidateHash: hash(candidates),
    progressHash: hash(progress),
    resinState: hash({
      currentResin: request.currentResin ?? null,
      maxResin: request.maxResin ?? null,
      availableMinutes: request.availableMinutes ?? null,
    }),
    promptVersion: DAILY_PLAN_PROMPT_VERSION,
    rulesVersion: DAILY_PLAN_RULES_VERSION,
    modelIdentifier,
  };
}

export function dailyPlanCacheKey(identity: DailyPlanCacheIdentity): string {
  return hash(identity);
}

export function dailyPlanInputHash(identity: DailyPlanCacheIdentity): string {
  return hash({ ...identity, clientScope: "redacted" });
}

function hash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}
