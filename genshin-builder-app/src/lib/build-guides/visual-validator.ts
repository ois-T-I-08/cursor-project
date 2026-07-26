import { PUBLISHABLE_PURPOSES, type VideoVisualAnalysisResult } from "./visual-schemas";

export class VisualValidationError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "VisualValidationError";
  }
}

const PERCENT_MAX = 500;
const MIN_CONFIDENCE = 0.45;

export type ValidatedVisualEvidence = {
  startSeconds: number;
  endSeconds: number;
  evidenceType: string;
  exactVisibleText: string;
  confidence: number;
  purposeSummary: string;
  validationStatus: "validated" | "rejected";
  exclusionCode: string;
  normalizedPayload: unknown;
  publishableStatValues: Array<{
    statKey: string;
    unit: "flat" | "percent";
    minimum: number | null;
    recommended: number | null;
    maximum: number | null;
    purpose: string;
    exactVisibleText: string;
    condition: string;
    confidence: number;
  }>;
  visibleTexts: Array<{ text: string; category: string; confidence: number }>;
  targetCharacterIds: string[];
};

export function validateVisualAnalysisResult(input: {
  expectedVideoId: string;
  durationSeconds: number | null;
  allowedCharacterIds: Set<string>;
  knownCharacterIds: Set<string>;
  result: VideoVisualAnalysisResult;
}): ValidatedVisualEvidence[] {
  if (input.result.videoId !== input.expectedVideoId) {
    throw new VisualValidationError("videoIdMismatch");
  }

  const out: ValidatedVisualEvidence[] = [];
  for (const evidence of input.result.evidences) {
    if (evidence.videoId !== input.expectedVideoId) {
      out.push(reject(evidence, "evidenceVideoIdMismatch"));
      continue;
    }
    if (evidence.startSeconds > evidence.endSeconds) {
      out.push(reject(evidence, "timestampOrderInvalid"));
      continue;
    }
    if (
      input.durationSeconds != null &&
      (evidence.endSeconds > input.durationSeconds + 1 ||
        evidence.startSeconds > input.durationSeconds + 1)
    ) {
      out.push(reject(evidence, "timestampBeyondDuration"));
      continue;
    }
    if (!evidence.readable || evidence.evidenceType === "unreadable") {
      out.push(reject(evidence, "unreadable"));
      continue;
    }
    if (evidence.confidence < MIN_CONFIDENCE) {
      out.push(reject(evidence, "confidenceBelowThreshold"));
      continue;
    }

    const targetCharacterIds = evidence.targetCharacterIds.filter((id) => {
      if (!input.knownCharacterIds.has(id)) return false;
      if (input.allowedCharacterIds.size > 0 && !input.allowedCharacterIds.has(id)) {
        return false;
      }
      return true;
    });

    const publishableStatValues = [];
    for (const stat of evidence.statValues) {
      if (!PUBLISHABLE_PURPOSES.has(stat.purpose as never)) continue;
      if (stat.purpose === "unknown") continue;
      if (stat.confidence < MIN_CONFIDENCE) continue;
      if (
        !numberInVisibleText(stat.exactVisibleText, [
          stat.minimum,
          stat.recommended,
          stat.maximum,
        ])
      ) {
        continue;
      }
      if (
        stat.minimum != null &&
        stat.maximum != null &&
        stat.minimum > stat.maximum
      ) {
        continue;
      }
      if (
        stat.recommended != null &&
        ((stat.minimum != null && stat.recommended < stat.minimum) ||
          (stat.maximum != null && stat.recommended > stat.maximum))
      ) {
        continue;
      }
      if (stat.unit === "percent") {
        for (const value of [stat.minimum, stat.recommended, stat.maximum]) {
          if (value != null && value > PERCENT_MAX) continue;
        }
        if (
          [stat.minimum, stat.recommended, stat.maximum].some(
            (value) => value != null && value > PERCENT_MAX,
          )
        ) {
          continue;
        }
      }
      publishableStatValues.push(stat);
    }

    out.push({
      startSeconds: evidence.startSeconds,
      endSeconds: evidence.endSeconds,
      evidenceType: evidence.evidenceType,
      exactVisibleText: evidence.visibleTexts[0]?.text?.slice(0, 200) ??
        evidence.statValues[0]?.exactVisibleText?.slice(0, 200) ??
        evidence.visualSummary.slice(0, 200),
      confidence: evidence.confidence,
      purposeSummary: [...new Set(evidence.statValues.map((s) => s.purpose))].join(","),
      validationStatus: publishableStatValues.length > 0 ? "validated" : "rejected",
      exclusionCode:
        publishableStatValues.length > 0 ? "" : "noPublishableStats",
      normalizedPayload: {
        recommendedMainStats: evidence.recommendedMainStats,
        statPriority: evidence.statPriority,
        weaponMentions: evidence.weaponMentions.map((w) => ({
          ...w,
          normalizedWeaponId: w.normalizedWeaponId,
        })),
        artifactSetMentions: evidence.artifactSetMentions.map((a) => ({
          ...a,
          normalizedArtifactSetId: a.normalizedArtifactSetId,
        })),
        warnings: evidence.warnings,
      },
      publishableStatValues,
      visibleTexts: evidence.visibleTexts,
      targetCharacterIds,
    });
  }
  return out;
}

function reject(
  evidence: VideoVisualAnalysisResult["evidences"][number],
  code: string,
): ValidatedVisualEvidence {
  return {
    startSeconds: evidence.startSeconds,
    endSeconds: evidence.endSeconds,
    evidenceType: evidence.evidenceType,
    exactVisibleText: evidence.visualSummary.slice(0, 200),
    confidence: evidence.confidence,
    purposeSummary: evidence.statValues.map((s) => s.purpose).join(","),
    validationStatus: "rejected",
    exclusionCode: code,
    normalizedPayload: {},
    publishableStatValues: [],
    visibleTexts: evidence.visibleTexts,
    targetCharacterIds: evidence.targetCharacterIds,
  };
}

function numberInVisibleText(
  text: string,
  values: Array<number | null>,
): boolean {
  const normalized = text.replace(/,/g, "");
  return values.some((value) => {
    if (value == null) return false;
    const asInt = String(Math.round(value));
    const asOne = value.toFixed(1).replace(/\.0$/, "");
    return normalized.includes(asInt) || normalized.includes(asOne);
  });
}
