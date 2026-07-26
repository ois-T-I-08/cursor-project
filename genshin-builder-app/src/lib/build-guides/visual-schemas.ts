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

export const guideStatKeySchema = z.enum(STAT_KEYS);
export type GuideStatKey = (typeof STAT_KEYS)[number];

export const VISUAL_VALUE_PURPOSES = [
  "explicit_recommendation",
  "minimum_requirement",
  "comfortable_target",
  "recommended_range",
  "example_build",
  "creator_current_build",
  "comparison_build",
  "damage_test_build",
  "before_after_comparison",
  "unknown",
] as const;

export const PUBLISHABLE_PURPOSES = new Set([
  "explicit_recommendation",
  "minimum_requirement",
  "comfortable_target",
  "recommended_range",
] as const);

export const visualValuePurposeSchema = z.enum(VISUAL_VALUE_PURPOSES);

const characterIdSchema = z
  .string()
  .regex(/^[a-z0-9][a-z0-9_-]{0,63}$/i)
  .max(64);

const statNumberSchema = z.number().finite().min(0).max(1_000_000).nullable();

export const visibleTextSchema = z.strictObject({
  text: z.string().min(1).max(300),
  confidence: z.number().min(0).max(1),
  category: z.enum([
    "stat_label",
    "stat_value",
    "weapon_name",
    "artifact_set",
    "main_stat",
    "substat_priority",
    "condition",
    "heading",
    "other",
  ]),
});

export const visualStatValueSchema = z.strictObject({
  statKey: guideStatKeySchema,
  unit: z.enum(["flat", "percent"]),
  minimum: statNumberSchema,
  recommended: statNumberSchema,
  maximum: statNumberSchema,
  purpose: visualValuePurposeSchema,
  exactVisibleText: z.string().min(1).max(200),
  condition: z.string().max(500).default(""),
  confidence: z.number().min(0).max(1),
});

export const videoVisualEvidenceSchema = z.strictObject({
  videoId: z.string().min(1).max(32),
  startSeconds: z.number().nonnegative(),
  endSeconds: z.number().nonnegative(),
  evidenceType: z.enum([
    "recommendation_table",
    "build_summary_slide",
    "character_status_screen",
    "artifact_screen",
    "weapon_screen",
    "comparison_table",
    "on_screen_text",
    "unreadable",
    "other",
  ]),
  targetCharacterIds: z.array(characterIdSchema).max(10).default([]),
  visibleTexts: z.array(visibleTextSchema).max(100).default([]),
  statValues: z.array(visualStatValueSchema).max(30).default([]),
  recommendedMainStats: z
    .strictObject({
      sands: z.array(z.string().max(64)).max(5),
      goblet: z.array(z.string().max(64)).max(5),
      circlet: z.array(z.string().max(64)).max(5),
    })
    .nullable()
    .default(null),
  statPriority: z.array(z.string().max(100)).max(20).default([]),
  weaponMentions: z
    .array(
      z.strictObject({
        exactVisibleText: z.string().max(100),
        normalizedWeaponId: z.string().max(64).nullable(),
        confidence: z.number().min(0).max(1),
      }),
    )
    .max(20)
    .default([]),
  artifactSetMentions: z
    .array(
      z.strictObject({
        exactVisibleText: z.string().max(100),
        normalizedArtifactSetId: z.string().max(64).nullable(),
        confidence: z.number().min(0).max(1),
      }),
    )
    .max(20)
    .default([]),
  visualSummary: z.string().max(500).default(""),
  confidence: z.number().min(0).max(1),
  readable: z.boolean(),
  warnings: z.array(z.string().max(300)).max(20).default([]),
});

export const videoVisualAnalysisResultSchema = z.strictObject({
  videoId: z.string().min(1).max(32),
  relevant: z.boolean(),
  detectedCharacterIds: z.array(characterIdSchema).max(20).default([]),
  evidences: z.array(videoVisualEvidenceSchema).max(80).default([]),
  unresolvedEntities: z
    .array(
      z.strictObject({
        exactVisibleText: z.string().max(100),
        type: z.enum(["character", "weapon", "artifact_set", "stat", "other"]),
        timestampSeconds: z.number().nonnegative(),
      }),
    )
    .max(40)
    .default([]),
  analysisSummary: z.string().max(1000).default(""),
});

export type VideoVisualAnalysisResult = z.infer<typeof videoVisualAnalysisResultSchema>;
export type VideoVisualEvidence = z.infer<typeof videoVisualEvidenceSchema>;
export type VisualStatValue = z.infer<typeof visualStatValueSchema>;

export const publicBuildRecommendationSchema = z.strictObject({
  characterId: z.string(),
  label: z.literal("動画内推奨目安"),
  status: z.literal("published"),
  origin: z.enum(["single_video", "merged"]),
  overallConfidence: z.number().min(0).max(1),
  context: z.strictObject({
    role: z.string().max(64).optional(),
    teamArchetype: z.string().max(64).optional(),
    weaponPreference: z.string().max(128).optional(),
    notes: z.string().max(500).optional(),
  }),
  mainStats: z.array(
    z.strictObject({
      slot: z.enum(["sands", "goblet", "circlet"]),
      stats: z.array(z.string().max(64)).max(6),
    }),
  ),
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
      exactVisibleText: z.string().max(200),
      startSeconds: z.number().nonnegative(),
      endSeconds: z.number().nonnegative(),
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
