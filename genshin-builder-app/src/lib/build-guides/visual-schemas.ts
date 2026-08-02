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

const recommendationLevelSchema = z.enum([
  "strongly_recommended",
  "recommended",
  "situational",
  "alternative",
]);

const publicSourceSchema = z.strictObject({
  id: z.string().min(1).max(64),
  videoId: z.string(),
  title: z.string(),
  channelId: z.string().max(64).nullable().optional(),
  channelTitle: z.string(),
  sourceUrl: z.string().url(),
  publishedAt: z.string().datetime().nullable().optional(),
  reviewedAt: z.string().datetime().nullable().optional(),
  gameVersion: z.string().max(32).nullable().optional(),
});

const publicWeaponSchema = z.strictObject({
  weaponId: z.string().max(64).nullable().optional(),
  displayName: z.string().max(64).nullable().optional(),
  rank: z.number().int().positive().nullable().optional(),
  recommendationLevel: recommendationLevelSchema.nullable().optional(),
  reason: z.string().max(500).nullable().optional(),
  conditions: z.array(z.string().max(200)).max(8),
  role: z.string().max(64).nullable().optional(),
  citationId: z.string().max(64).nullable().optional(),
  dataOrigin: z.enum(["structured", "legacy_preference"]),
});

const publicArtifactRecommendationSchema = z.strictObject({
  sets: z
    .array(
      z.strictObject({
        setId: z.string().min(1).max(64),
        pieces: z.number().int().positive().max(5),
      }),
    )
    .min(1)
    .max(4),
  rank: z.number().int().positive().nullable().optional(),
  recommendationLevel: recommendationLevelSchema.nullable().optional(),
  reason: z.string().max(500).nullable().optional(),
  conditions: z.array(z.string().max(200)).max(8),
  role: z.string().max(64).nullable().optional(),
  isAlternative: z.boolean(),
  citationId: z.string().max(64).nullable().optional(),
});

const publicMainStatSchema = z.strictObject({
  slot: z.enum(["sands", "goblet", "circlet"]),
  primaryStats: z.array(z.string().max(64)).min(1).max(4),
  alternativeStats: z.array(z.string().max(64)).max(4),
  /** モバイル互換: primary + alternative */
  stats: z.array(z.string().max(64)).min(1).max(6),
  condition: z.string().max(500).nullable().optional(),
  citationId: z.string().max(64).nullable().optional(),
});

const publicRecommendedStatSchema = z.strictObject({
  stat: guideStatKeySchema,
  valueType: z.enum(["minimum", "maximum", "range", "target", "ratio"]),
  minimum: z.number().finite().nullable().optional(),
  maximum: z.number().finite().nullable().optional(),
  recommended: z.number().finite().nullable().optional(),
  unit: z.enum(["flat", "percent"]).nullable().optional(),
  condition: z.string().max(500).nullable().optional(),
  citationId: z.string().max(64).nullable().optional(),
  leftStat: guideStatKeySchema.nullable().optional(),
  leftValue: z.number().finite().nullable().optional(),
  rightStat: guideStatKeySchema.nullable().optional(),
  rightValue: z.number().finite().nullable().optional(),
});

export const publicBuildRecommendationSchema = z.strictObject({
  schemaVersion: z.literal(1),
  characterId: z.string(),
  label: z.literal("動画内推奨目安"),
  status: z.literal("published"),
  origin: z.enum(["single_video", "merged"]),
  overallConfidence: z.number().min(0).max(1),
  investmentPriority: z.enum(["high", "medium", "low"]).optional(),
  gameVersion: z.string().max(32).optional(),
  context: z.strictObject({
    role: z.string().max(64).optional(),
    teamArchetype: z.string().max(64).optional(),
    weaponPreference: z.string().max(128).optional(),
    notes: z.string().max(500).optional(),
  }),
  weapons: z.array(publicWeaponSchema).max(12),
  artifactRecommendations: z.array(publicArtifactRecommendationSchema).max(12),
  mainStats: z.array(publicMainStatSchema).max(6),
  recommendedStats: z.array(publicRecommendedStatSchema).max(20),
  /** 既存クライアント互換 */
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
  updatedAt: z.string().datetime().nullable(),
  sources: z.array(publicSourceSchema),
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
