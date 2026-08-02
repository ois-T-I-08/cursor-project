import { z } from "zod";
import type { DailyPlanEnrichRequest } from "./types";

const itemTypeSchema = z.enum([
  "weekdayMaterial",
  "weeklyBoss",
  "growthGoal",
  "generalMaterial",
]);

const itemSchema = z.object({
  id: z.string().trim().min(1).max(128),
  type: itemTypeSchema,
  title: z.string().trim().min(1).max(200),
  priority: z.number().int().min(0).max(200),
  reasons: z.array(z.string().trim().max(200)).max(6).default([]),
  characterIds: z.array(z.string().trim().max(64)).max(8).default([]),
  materialIds: z.array(z.string().trim().max(64)).max(12).default([]),
  estimatedResinCost: z.number().int().min(0).max(1000).nullable().optional(),
});

const requestSchema = z.object({
  weekday: z.number().int().min(1).max(7),
  currentResin: z.number().int().min(0).max(1000).nullable().optional(),
  maxResin: z.number().int().min(0).max(1000).nullable().optional(),
  items: z.array(itemSchema).min(1).max(12),
});

export function parseDailyPlanEnrichRequest(value: unknown): DailyPlanEnrichRequest {
  const parsed = requestSchema.parse(value);
  const seen = new Set<string>();
  const items = parsed.items.filter((item) => {
    if (seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
  if (items.length === 0) {
    throw new z.ZodError([
      {
        code: "custom",
        path: ["items"],
        message: "at least one unique item required",
      },
    ]);
  }
  return { ...parsed, items };
}

const aiResponseSchema = z.object({
  orderedItemIds: z.array(z.string().trim().min(1).max(128)).min(1).max(12),
  reasonsByItemId: z
    .record(z.string(), z.array(z.string().trim().min(1).max(200)).max(4))
    .optional()
    .default({}),
});

export function parseDailyPlanAiResponse(value: unknown): {
  orderedItemIds: string[];
  reasonsByItemId: Record<string, string[]>;
} {
  return aiResponseSchema.parse(value);
}
