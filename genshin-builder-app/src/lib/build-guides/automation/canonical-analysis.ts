import { z } from "zod";
import type { AnalysisValidationResult } from "./analysis-schema";
import { automationHash } from "./idempotency";

const canonicalClaimSchema = z
  .object({
    claimId: z.string().min(1).max(100),
    kind: z.enum([
      "weapon",
      "artifact_set",
      "main_stat",
      "sub_stat",
      "target",
      "investment",
    ]),
    entityId: z.string().min(1).max(100).nullable(),
    slot: z.string().min(1).max(100).nullable(),
    value: z.string().min(1).max(500),
    condition: z.string().max(500),
    confidence: z.number().min(0).max(1),
    evidenceSegmentIds: z.array(z.string().min(1)).min(1).max(20),
    evidenceHash: z.string().regex(/^[a-f0-9]{64}$/),
    startSeconds: z.number().nonnegative(),
    endSeconds: z.number().positive(),
  })
  .strict()
  .refine((claim) => claim.endSeconds >= claim.startSeconds, {
    message: "invalidEvidenceRange",
  });

export const canonicalValidatedAnalysisSchema = z
  .object({
    schemaVersion: z.string().min(1).max(100),
    characterId: z.string().min(1).max(100),
    transcriptHash: z.string().regex(/^[a-f0-9]{64}$/),
    analysisIdempotencyKey: z.string().regex(/^[a-f0-9]{64}$/),
    providerId: z.string().min(1).max(100),
    modelIdentifier: z.string().min(1).max(200),
    promptVersion: z.string().min(1).max(100),
    overallConfidence: z.number().min(0).max(1),
    claims: z.array(canonicalClaimSchema).min(1).max(200),
    quality: z
      .object({
        claimCount: z.number().int().positive(),
        citationCoverage: z.literal(1),
        timestampCoverage: z.literal(1),
        entityCoverage: z.literal(1),
        minClaimConfidence: z.number().min(0).max(1),
        overallConfidence: z.number().min(0).max(1),
      })
      .strict(),
  })
  .strict();

export type CanonicalValidatedAnalysis = z.infer<
  typeof canonicalValidatedAnalysisSchema
>;
export type CanonicalValidatedClaim = z.infer<typeof canonicalClaimSchema>;

export function canonicalizeValidatedAnalysis(input: {
  validation: Extract<AnalysisValidationResult, { ok: true }>;
  transcriptHash: string;
  analysisIdempotencyKey: string;
  providerId: string;
  modelIdentifier: string;
  promptVersion: string;
}): {
  canonical: CanonicalValidatedAnalysis;
  payload: string;
  validationHash: string;
} {
  const canonical = canonicalValidatedAnalysisSchema.parse({
    schemaVersion: input.validation.analysis.schemaVersion,
    characterId: input.validation.analysis.characterId,
    transcriptHash: input.transcriptHash,
    analysisIdempotencyKey: input.analysisIdempotencyKey,
    providerId: input.providerId,
    modelIdentifier: input.modelIdentifier,
    promptVersion: input.promptVersion,
    overallConfidence: input.validation.analysis.overallConfidence,
    claims: input.validation.claims.map(({ evidenceText, ...claim }) => ({
      ...claim,
      evidenceHash: automationHash("youtube-evidence-text-v1", evidenceText),
    })),
    quality: input.validation.quality,
  });
  const payload = JSON.stringify(canonical);
  return {
    canonical,
    payload,
    validationHash: automationHash(
      "youtube-canonical-validation-v1",
      canonical,
    ),
  };
}

export function parseCanonicalValidatedAnalysis(input: {
  payload: string;
  validationHash: string;
}): CanonicalValidatedAnalysis {
  const parsed = canonicalValidatedAnalysisSchema.parse(JSON.parse(input.payload));
  const actualHash = automationHash(
    "youtube-canonical-validation-v1",
    parsed,
  );
  if (actualHash !== input.validationHash) {
    throw new Error("CANONICAL_VALIDATION_HASH_MISMATCH");
  }
  return parsed;
}
