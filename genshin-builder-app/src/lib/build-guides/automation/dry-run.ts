import type { PipelineStatus } from "./state-machine";

export type DryRunGateInput = {
  sourceCount: number;
  channelAllowed: boolean;
  transcriptAvailable: boolean;
  schemaValid: boolean;
  entityCoverage: number;
  citationCoverage: number;
  timestampCoverage: number;
  evidenceMatches: boolean;
  confidence: number;
  conflicts: string[];
};

export type DryRunGateResult = {
  status: Extract<PipelineStatus, "READY_TO_PUBLISH" | "BLOCKED">;
  publishAllowed: false;
  blockCodes: string[];
};

export function evaluateDryRunGate(
  input: DryRunGateInput,
  thresholds: {
    minConfidence: number;
    entityCoverage: number;
    citationCoverage: number;
    timestampCoverage: number;
  },
): DryRunGateResult {
  const blockCodes: string[] = [];
  if (input.sourceCount !== 1) blockCodes.push("BLOCKED_MULTI_SOURCE_DRY_RUN");
  if (!input.channelAllowed) blockCodes.push("BLOCKED_SOURCE_NOT_ALLOWED");
  if (!input.transcriptAvailable) blockCodes.push("BLOCKED_TRANSCRIPT_UNAVAILABLE");
  if (!input.schemaValid) blockCodes.push("BLOCKED_SCHEMA_INVALID");
  if (input.entityCoverage < thresholds.entityCoverage) {
    blockCodes.push("BLOCKED_UNKNOWN_ENTITY");
  }
  if (input.citationCoverage < thresholds.citationCoverage) {
    blockCodes.push("BLOCKED_UNRESOLVED_CITATION");
  }
  if (input.timestampCoverage < thresholds.timestampCoverage) {
    blockCodes.push("BLOCKED_TIMESTAMP_INVALID");
  }
  if (!input.evidenceMatches) blockCodes.push("BLOCKED_EVIDENCE_MISMATCH");
  if (input.confidence < thresholds.minConfidence) {
    blockCodes.push("BLOCKED_LOW_CONFIDENCE");
  }
  if (input.conflicts.length > 0) blockCodes.push("BLOCKED_CONFLICT");
  return {
    status: blockCodes.length === 0 ? "READY_TO_PUBLISH" : "BLOCKED",
    publishAllowed: false,
    blockCodes,
  };
}
