import { z } from "zod";

import { DAILY_PLAN_ITEM_TYPES } from "./types";
import type {
  DailyPlanAiResult,
  DailyPlanEnrichRequest,
  DailyPlanProposal,
} from "./types";

const taskIdSchema = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9:_|.-]{1,128}$/);
const relatedIdSchema = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9:_|.-]{1,96}$/);
const safeTextSchema = z.string().trim().min(1).max(120);

const candidateSchema = z.strictObject({
  taskId: taskIdSchema,
  type: z.enum(DAILY_PLAN_ITEM_TYPES),
  title: z.string().trim().min(1).max(160),
  characterIds: z.array(relatedIdSchema).max(8),
  materialIds: z.array(relatedIdSchema).max(16),
  currentLevel: z.number().int().min(0).max(1000).nullable().optional(),
  targetLevel: z.number().int().min(0).max(1000).nullable().optional(),
  estimatedResinCost: z.number().int().min(0).max(2000).nullable().optional(),
  estimatedMinutes: z.number().int().min(5).max(180).nullable().optional(),
  availableToday: z.boolean(),
  requiresResin: z.boolean(),
  bookmarked: z.boolean(),
  existingPriority: z.number().int().min(0).max(200),
  reasonFacts: z.array(safeTextSchema).max(8),
});

const requestSchema = z
  .strictObject({
    clientScope: z.string().regex(/^[a-f0-9]{12,64}$/),
    date: z.iso.date(),
    timezone: z
      .string()
      .trim()
      .regex(/^[A-Za-z0-9_+:/.+-]{1,64}$/),
    weekday: z.number().int().min(1).max(7),
    currentResin: z.number().int().min(0).max(1000).nullable().optional(),
    maxResin: z.number().int().min(0).max(1000).nullable().optional(),
    availableMinutes: z.number().int().min(5).max(1440).nullable().optional(),
    force: z.boolean().optional(),
    candidates: z.array(candidateSchema).min(1).max(20),
  })
  .superRefine((value, context) => {
    const seen = new Set<string>();
    value.candidates.forEach((candidate, index) => {
      if (seen.has(candidate.taskId)) {
        context.addIssue({
          code: "custom",
          path: ["candidates", index, "taskId"],
          message: "duplicate taskId",
        });
      }
      seen.add(candidate.taskId);
      if (
        candidate.currentLevel != null &&
        candidate.targetLevel != null &&
        candidate.targetLevel < candidate.currentLevel
      ) {
        context.addIssue({
          code: "custom",
          path: ["candidates", index, "targetLevel"],
          message: "targetLevel must be at least currentLevel",
        });
      }
    });
    if (
      value.currentResin != null &&
      value.maxResin != null &&
      value.currentResin > value.maxResin
    ) {
      context.addIssue({
        code: "custom",
        path: ["currentResin"],
        message: "currentResin must not exceed maxResin",
      });
    }
  });

const recommendationSchema = z.strictObject({
  taskId: taskIdSchema,
  priority: z.number().int().min(1).max(5),
  category: z.literal("do_today"),
  reason: safeTextSchema,
  suggestedMinutes: z.number().int().min(5).max(180),
});

const aiResponseSchema = z.strictObject({
  summary: safeTextSchema,
  recommendations: z.array(recommendationSchema).min(1).max(5),
  deferredTaskIds: z.array(taskIdSchema).max(20),
  warnings: z.array(safeTextSchema).max(5),
});

const proposalSchema = aiResponseSchema.extend({
  source: z.enum(["deepseek", "deterministic_fallback"]),
  generatedAt: z.iso.datetime({ offset: true }),
  inputHash: z.string().regex(/^[a-f0-9]{64}$/),
  modelIdentifier: z.string().trim().min(1).max(80).optional(),
});

export function parseDailyPlanEnrichRequest(value: unknown): DailyPlanEnrichRequest {
  return requestSchema.parse(value);
}

export function parseDailyPlanAiResponse(value: unknown): DailyPlanAiResult {
  return aiResponseSchema.parse(value);
}

export function parseDailyPlanProposal(value: unknown): DailyPlanProposal {
  return proposalSchema.parse(value);
}
