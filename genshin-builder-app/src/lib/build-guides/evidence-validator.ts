import type { NormalizedTranscript } from "./transcript";
import type { AiGuideExtraction, ValidatedGuidePayload } from "./schemas";
import { validatedGuidePayloadSchema } from "./schemas";

export class EvidenceValidationError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "EvidenceValidationError";
  }
}

function normalizeForMatch(value: string): string {
  return value.replace(/\s+/g, " ").trim().toLowerCase();
}

export function snippetExistsInTranscript(
  snippet: string,
  transcript: NormalizedTranscript,
): boolean {
  const needle = normalizeForMatch(snippet);
  if (!needle) return false;
  if (normalizeForMatch(transcript.normalizedText).includes(needle)) return true;
  return transcript.segments.some((segment) =>
    normalizeForMatch(segment.text).includes(needle),
  );
}

function assertTimestampAgainstSegment(
  evidence: {
    startMs?: number | null;
    endMs?: number | null;
    segmentIndex?: number | null;
  },
  transcript: NormalizedTranscript,
): void {
  if (evidence.startMs == null && evidence.endMs == null) return;
  if (evidence.segmentIndex == null) {
    // Timestamps without a segment cannot be verified against source segments.
    throw new EvidenceValidationError("evidenceTimestampUnanchored");
  }
  const segment = transcript.segments[evidence.segmentIndex];
  if (!segment) throw new EvidenceValidationError("evidenceSegmentMissing");
  if (evidence.startMs != null && segment.startMs != null && evidence.startMs !== segment.startMs) {
    throw new EvidenceValidationError("evidenceStartMismatch");
  }
  if (evidence.endMs != null && segment.endMs != null && evidence.endMs !== segment.endMs) {
    throw new EvidenceValidationError("evidenceEndMismatch");
  }
}

export function validateEvidenceAgainstTranscript(
  extraction: AiGuideExtraction,
  transcript: NormalizedTranscript,
): void {
  const withEvidence = [
    ...extraction.mainStats.map((item) => item.evidence),
    ...extraction.targets.map((item) => item.evidence),
  ].filter(Boolean);

  for (const evidence of withEvidence) {
    if (!evidence) continue;
    if (!snippetExistsInTranscript(evidence.snippet, transcript)) {
      throw new EvidenceValidationError("evidenceSnippetMismatch");
    }
    if (evidence.segmentIndex != null) {
      const segment = transcript.segments[evidence.segmentIndex];
      if (!segment) throw new EvidenceValidationError("evidenceSegmentMissing");
      if (!normalizeForMatch(segment.text).includes(normalizeForMatch(evidence.snippet))) {
        throw new EvidenceValidationError("evidenceSegmentMismatch");
      }
    }
    if (
      evidence.startMs != null &&
      evidence.endMs != null &&
      evidence.startMs > evidence.endMs
    ) {
      throw new EvidenceValidationError("evidenceTimestampInvalid");
    }
    assertTimestampAgainstSegment(evidence, transcript);
  }

  // Numeric targets that are not inferred must carry evidence for publish path.
  for (const target of extraction.targets) {
    if (target.inferred) continue;
    const hasNumber =
      target.recommended != null || target.min != null || target.max != null;
    if (hasNumber && !target.evidence?.snippet) {
      throw new EvidenceValidationError("evidenceRequiredForNumericTarget");
    }
  }
}

export function toValidatedPublishablePayload(
  extraction: AiGuideExtraction,
  characterId: string,
): ValidatedGuidePayload {
  const publishableTargets = extraction.targets.filter((target) => !target.inferred);
  return validatedGuidePayloadSchema.parse({
    characterId,
    context: extraction.context ?? {},
    mainStats: extraction.mainStats ?? [],
    substatPriority: extraction.substatPriority ?? [],
    targets: publishableTargets,
    overallConfidence: extraction.overallConfidence ?? 0,
    caveats: extraction.caveats ?? [],
    unresolvedEntities: extraction.unresolvedEntities ?? [],
  });
}
