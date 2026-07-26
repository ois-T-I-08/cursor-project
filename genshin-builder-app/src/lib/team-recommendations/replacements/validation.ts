import { z } from "zod";
import { NORMALIZED_TEAM_ROLES, TEAM_SOURCES } from "./types";
import type {
  CharacterTeamProfile,
  ImportedTeam,
  ReplacementResult,
} from "./types";

const safeText = z.string().trim().min(1).max(160);
const characterId = z.string().regex(/^\d{5,12}(?:-[a-z0-9_-]{1,24})?$/i);
const isoDate = z.iso.datetime({ offset: true });

const importedTeamSchema = z.strictObject({
  source: z.enum(TEAM_SOURCES),
  sourceTeamId: safeText,
  name: safeText,
  archetype: z.string().trim().max(80).optional(),
  characters: z
    .array(
      z.strictObject({
        characterId,
        sourceRole: z.string().trim().max(80).optional(),
        slotIndex: z.int().min(0).max(3),
      }),
    )
    .length(4),
  sourceUrl: z.url().max(500).optional(),
  sourceUpdatedAt: isoDate.optional(),
  fetchedAt: isoDate,
  dataVersion: safeText.max(80),
});

const importedTeamCollectionSchema = z.strictObject({
  schemaVersion: z.literal(1),
  teams: z.array(importedTeamSchema).max(500),
});

const stringList = z.array(z.string().trim().min(1).max(120)).max(32);

export const characterTeamProfileSchema = z.strictObject({
  characterId,
  element: z.enum([
    "pyro",
    "hydro",
    "electro",
    "cryo",
    "anemo",
    "geo",
    "dendro",
  ]),
  weaponType: z
    .enum(["sword", "claymore", "polearm", "bow", "catalyst"])
    .optional(),
  roles: stringList,
  tags: stringList,
  fieldTime: z.enum(["none", "low", "medium", "high"]),
  damagePosition: z.enum(["on_field", "off_field", "both", "none"]),
  application: z
    .strictObject({
      elements: stringList,
      strength: z.string().max(40).optional(),
      frequency: z.string().max(40).optional(),
      offField: z.boolean(),
    })
    .optional(),
  triggers: stringList.optional(),
  utility: z
    .strictObject({
      healing: z.string().max(40).optional(),
      shielding: z.string().max(40).optional(),
      interruptionResistance: z.boolean().optional(),
      damageReduction: z.boolean().optional(),
      grouping: z.boolean().optional(),
      energyGeneration: z.string().max(40).optional(),
    })
    .optional(),
  buffs: z
    .strictObject({
      targets: stringList.optional(),
      types: stringList.optional(),
    })
    .optional(),
  restrictions: stringList.optional(),
  dataVersion: safeText.max(80),
});

const characterTeamProfileCollectionSchema = z.strictObject({
  schemaVersion: z.literal(1),
  gameVersion: z.string().trim().min(1).max(40),
  dataVersion: z.string().trim().min(1).max(80),
  profiles: z.array(characterTeamProfileSchema).max(200),
});

const score = z.number().finite().min(0).max(100);
const shortList = z.array(z.string().trim().min(1).max(160)).max(3);

const slotAnalysisSchema = z.strictObject({
  requiredFunctions: stringList,
  preferredFunctions: stringList,
  dependencies: stringList,
  replacementRisks: stringList,
});

const aiCandidateSchema = z.strictObject({
  characterId,
  compatibilityScore: score,
  category: z.enum([
    "optimal",
    "conditional",
    "compromise",
    "not_recommended",
  ]),
  confidence: z.number().finite().min(0).max(1),
  reasons: shortList,
  tradeoffs: shortList,
  requiredChanges: shortList,
  teamEvaluation: z.strictObject({
    reactionViability: score,
    damageBalance: score,
    sustain: score,
    energy: score,
    fieldTimeBalance: score,
  }),
});

export const aiReplacementResultSchema = z.strictObject({
  slotAnalysis: z.strictObject({
    requiredFunctions: stringList,
    preferredFunctions: stringList,
    dependencies: stringList,
    replacementRisks: stringList,
  }),
  candidates: z.array(aiCandidateSchema).max(20),
});

export const replacementResultSchema = z.strictObject({
  slotAnalysis: slotAnalysisSchema,
  candidates: z
    .array(
      aiCandidateSchema.extend({
        deterministicPenalty: z.number().int().min(0).max(100).optional(),
        finalScore: score.optional(),
      }),
    )
    .max(20),
});

export function parseImportedTeamCollection(value: unknown): ImportedTeam[] {
  return importedTeamCollectionSchema.parse(value).teams;
}

export function parseCharacterTeamProfile(value: unknown): CharacterTeamProfile {
  return characterTeamProfileSchema.parse(value);
}

export function parseCharacterTeamProfileCollection(value: unknown): {
  gameVersion: string;
  dataVersion: string;
  profiles: CharacterTeamProfile[];
} {
  return characterTeamProfileCollectionSchema.parse(value);
}

export function parseReplacementResult(value: unknown): ReplacementResult {
  return replacementResultSchema.parse(value);
}

export function parseAiReplacementResult(value: unknown): ReplacementResult {
  return aiReplacementResultSchema.parse(value);
}

export function normalizedRoleIsValid(value: string): boolean {
  return (NORMALIZED_TEAM_ROLES as readonly string[]).includes(value);
}
