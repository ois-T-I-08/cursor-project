import { z } from "zod";

export const STAT_KEYS = [
  "hp",
  "atk",
  "def",
  "em",
  "critRate",
  "critDmg",
  "er",
  "healing",
  "elemDmg",
  "physDmg",
] as const;

export type GuideStatKey = (typeof STAT_KEYS)[number];

export const guideStatKeySchema = z.enum(STAT_KEYS);

const characterIdSchema = z
  .string()
  .regex(/^[a-z0-9][a-z0-9_-]{0,63}$/i)
  .max(64);

const snippetSchema = z.string().trim().min(1).max(200);

export const evidenceSchema = z.strictObject({
  snippet: snippetSchema,
  startMs: z.number().int().nonnegative().nullable().optional(),
  endMs: z.number().int().nonnegative().nullable().optional(),
  segmentIndex: z.number().int().nonnegative().nullable().optional(),
});

/** Reject negatives and absurd outliers before publish. */
const statNumberSchema = z
  .number()
  .finite()
  .min(0)
  .max(1_000_000);

export const statTargetSchema = z.strictObject({
  stat: guideStatKeySchema,
  recommended: statNumberSchema.optional(),
  min: statNumberSchema.optional(),
  max: statNumberSchema.optional(),
  unit: z.enum(["flat", "percent"]).optional(),
  confidence: z.number().min(0).max(1).optional(),
  inferred: z.boolean().optional().default(false),
  evidence: evidenceSchema.optional(),
});

export const mainStatSlotSchema = z.strictObject({
  slot: z.enum(["sands", "goblet", "circlet"]),
  stats: z.array(z.string().min(1).max(64)).min(1).max(6),
  confidence: z.number().min(0).max(1).optional(),
  evidence: evidenceSchema.optional(),
});

export const buildContextSchema = z.strictObject({
  role: z.string().max(64).optional(),
  teamArchetype: z.string().max(64).optional(),
  weaponPreference: z.string().max(128).optional(),
  notes: z.string().max(500).optional(),
});

export const aiGuideExtractionSchema = z.strictObject({
  characterId: characterIdSchema.optional(),
  characterNameHint: z.string().max(128).optional(),
  unresolvedEntities: z.array(z.string().max(128)).max(20).optional().default([]),
  context: buildContextSchema.optional().default({}),
  mainStats: z.array(mainStatSlotSchema).max(6).optional().default([]),
  substatPriority: z.array(guideStatKeySchema).max(10).optional().default([]),
  targets: z.array(statTargetSchema).max(20).optional().default([]),
  overallConfidence: z.number().min(0).max(1).optional().default(0),
  caveats: z.array(z.string().max(300)).max(10).optional().default([]),
});

export type AiGuideExtraction = z.infer<typeof aiGuideExtractionSchema>;

export const validatedGuidePayloadSchema = z.strictObject({
  characterId: characterIdSchema,
  context: buildContextSchema,
  mainStats: z.array(mainStatSlotSchema),
  substatPriority: z.array(guideStatKeySchema),
  targets: z.array(
    statTargetSchema.superRefine((value, ctx) => {
      if (value.inferred) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "inferredNotPublishable",
        });
      }
      if (
        value.min != null &&
        value.max != null &&
        value.min > value.max
      ) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "invalidRange" });
      }
      if (
        value.recommended != null &&
        value.min != null &&
        value.recommended < value.min
      ) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "recommendedBelowMin" });
      }
      if (
        value.recommended != null &&
        value.max != null &&
        value.recommended > value.max
      ) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "recommendedAboveMax" });
      }
    }),
  ),
  overallConfidence: z.number().min(0).max(1),
  caveats: z.array(z.string().max(300)).max(10),
  unresolvedEntities: z.array(z.string().max(128)).max(20),
});

export type ValidatedGuidePayload = z.infer<typeof validatedGuidePayloadSchema>;

export const publicBuildRecommendationSchema = z.strictObject({
  characterId: z.string(),
  label: z.literal("動画内推奨目安"),
  status: z.literal("published"),
  origin: z.enum(["single_video", "merged"]),
  overallConfidence: z.number().min(0).max(1),
  context: buildContextSchema,
  mainStats: z.array(mainStatSlotSchema),
  substatPriority: z.array(guideStatKeySchema),
  targets: z.array(
    z.strictObject({
      stat: guideStatKeySchema,
      recommended: z.number().finite().optional(),
      min: z.number().finite().optional(),
      max: z.number().finite().optional(),
      unit: z.enum(["flat", "percent"]).optional(),
    }),
  ),
  caveats: z.array(z.string()),
  lastVerifiedAt: z.string().datetime().nullable(),
  publishedAt: z.string().datetime().nullable(),
  sources: z.array(
    z.strictObject({
      videoId: z.string(),
      title: z.string(),
      channelTitle: z.string(),
      sourceUrl: z.string().url(),
      publishedAt: z.string().datetime().nullable().optional(),
    }),
  ),
  evidence: z.array(
    z.strictObject({
      fieldPath: z.string(),
      snippet: snippetSchema,
      startMs: z.number().int().nonnegative().nullable().optional(),
      endMs: z.number().int().nonnegative().nullable().optional(),
      videoId: z.string(),
    }),
  ),
});

export type PublicBuildRecommendation = z.infer<typeof publicBuildRecommendationSchema>;

export const permissionStatusSchema = z.enum([
  "unknown",
  "pending",
  "approved_for_processing",
  "denied",
]);
