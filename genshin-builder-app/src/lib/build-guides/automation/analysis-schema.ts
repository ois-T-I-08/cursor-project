import { z } from "zod";
import {
  normalizeTranscriptText,
  type NormalizedTranscript,
} from "./transcript-normalize";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

export const TRANSCRIPT_ANALYSIS_SCHEMA_VERSION = "transcript-analysis-v1";

export const transcriptClaimSchema = z
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
    evidenceText: z.string().min(1).max(2_000),
  })
  .strict();

export const transcriptAnalysisSchema = z
  .object({
    schemaVersion: z.literal(TRANSCRIPT_ANALYSIS_SCHEMA_VERSION),
    characterId: z.string().min(1).max(100),
    overallConfidence: z.number().min(0).max(1),
    claims: z.array(transcriptClaimSchema).min(1).max(200),
  })
  .strict();

export type TranscriptAnalysis = z.infer<typeof transcriptAnalysisSchema>;
export type TranscriptClaim = z.infer<typeof transcriptClaimSchema>;

export type ValidatedTranscriptClaim = TranscriptClaim &
  Readonly<{
    startSeconds: number;
    endSeconds: number;
  }>;

export type AnalysisValidationResult =
  | {
      ok: true;
      analysis: TranscriptAnalysis;
      claims: readonly ValidatedTranscriptClaim[];
      quality: {
        claimCount: number;
        citationCoverage: 1;
        timestampCoverage: 1;
        entityCoverage: 1;
        minClaimConfidence: number;
        overallConfidence: number;
      };
    }
  | {
      ok: false;
      blockCode:
        | "BLOCKED_ANALYSIS_SCHEMA_INVALID"
        | "BLOCKED_CHARACTER_MISMATCH"
        | "BLOCKED_UNKNOWN_ENTITY"
        | "BLOCKED_EVIDENCE_MISSING"
        | "BLOCKED_EVIDENCE_TEXT_MISMATCH"
        | "BLOCKED_CONFIDENCE_LOW";
      safeIssues: readonly string[];
    };

export function validateTranscriptAnalysis(
  value: unknown,
  context: {
    expectedCharacterId: string;
    knownEntityIds: ReadonlySet<string>;
    transcript: NormalizedTranscript;
  },
): AnalysisValidationResult {
  const parsed = transcriptAnalysisSchema.safeParse(value);
  if (!parsed.success) {
    return {
      ok: false,
      blockCode: "BLOCKED_ANALYSIS_SCHEMA_INVALID",
      safeIssues: parsed.error.issues.map(
        (issue) => `schema:${issue.path.join(".")}:${issue.code}`,
      ),
    };
  }
  const analysis = parsed.data;
  if (analysis.characterId !== context.expectedCharacterId) {
    return {
      ok: false,
      blockCode: "BLOCKED_CHARACTER_MISMATCH",
      safeIssues: ["characterId"],
    };
  }
  if (analysis.overallConfidence < YOUTUBE_AUTOMATION_POLICY.minOverallConfidence) {
    return {
      ok: false,
      blockCode: "BLOCKED_CONFIDENCE_LOW",
      safeIssues: ["overallConfidence"],
    };
  }
  const segmentById = new Map(
    context.transcript.segments.map((segment) => [segment.segmentKey, segment]),
  );
  const validated: ValidatedTranscriptClaim[] = [];
  for (const claim of analysis.claims) {
    if (
      claim.entityId &&
      !context.knownEntityIds.has(claim.entityId)
    ) {
      return {
        ok: false,
        blockCode: "BLOCKED_UNKNOWN_ENTITY",
        safeIssues: [`claim:${claim.claimId}:entityId`],
      };
    }
    if (claim.confidence < YOUTUBE_AUTOMATION_POLICY.minClaimConfidence) {
      return {
        ok: false,
        blockCode: "BLOCKED_CONFIDENCE_LOW",
        safeIssues: [`claim:${claim.claimId}:confidence`],
      };
    }
    const segments = claim.evidenceSegmentIds.map((id) => segmentById.get(id));
    if (segments.some((segment) => !segment)) {
      return {
        ok: false,
        blockCode: "BLOCKED_EVIDENCE_MISSING",
        safeIssues: [`claim:${claim.claimId}:evidenceSegmentIds`],
      };
    }
    const knownSegments = segments.filter(
      (segment): segment is NonNullable<typeof segment> => Boolean(segment),
    );
    const evidenceHaystack = normalizeForEvidence(
      knownSegments.map((segment) => segment.text).join(" "),
    );
    const evidenceNeedle = normalizeForEvidence(claim.evidenceText);
    if (!evidenceNeedle || !evidenceHaystack.includes(evidenceNeedle)) {
      return {
        ok: false,
        blockCode: "BLOCKED_EVIDENCE_TEXT_MISMATCH",
        safeIssues: [`claim:${claim.claimId}:evidenceText`],
      };
    }
    const startSeconds = Math.min(
      ...knownSegments.map((segment) => segment.startSeconds),
    );
    const endSeconds = Math.max(
      ...knownSegments.map(
        (segment) => segment.startSeconds + segment.durationSeconds,
      ),
    );
    validated.push({ ...claim, startSeconds, endSeconds });
  }
  return {
    ok: true,
    analysis,
    claims: validated,
    quality: {
      claimCount: validated.length,
      citationCoverage: 1,
      timestampCoverage: 1,
      entityCoverage: 1,
      minClaimConfidence: Math.min(
        ...validated.map((claim) => claim.confidence),
      ),
      overallConfidence: analysis.overallConfidence,
    },
  };
}

function normalizeForEvidence(value: string): string {
  return normalizeTranscriptText(value)
    .normalize("NFKC")
    .toLocaleLowerCase("ja")
    .replace(/[、。,.!！?？「」『』（）()\s]/g, "");
}

/**
 * Kept as data so providers can request schema-constrained JSON without
 * weakening validation performed locally after the response.
 */
export const TRANSCRIPT_ANALYSIS_JSON_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["schemaVersion", "characterId", "overallConfidence", "claims"],
  properties: {
    schemaVersion: {
      type: "string",
      enum: [TRANSCRIPT_ANALYSIS_SCHEMA_VERSION],
    },
    characterId: { type: "string" },
    overallConfidence: { type: "number", minimum: 0, maximum: 1 },
    claims: {
      type: "array",
      minItems: 1,
      maxItems: 200,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "claimId",
          "kind",
          "entityId",
          "slot",
          "value",
          "condition",
          "confidence",
          "evidenceSegmentIds",
          "evidenceText",
        ],
        properties: {
          claimId: { type: "string" },
          kind: {
            type: "string",
            enum: [
              "weapon",
              "artifact_set",
              "main_stat",
              "sub_stat",
              "target",
              "investment",
            ],
          },
          entityId: { type: ["string", "null"] },
          slot: { type: ["string", "null"] },
          value: { type: "string" },
          condition: { type: "string" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          evidenceSegmentIds: {
            type: "array",
            minItems: 1,
            items: { type: "string" },
          },
          evidenceText: { type: "string" },
        },
      },
    },
  },
});

