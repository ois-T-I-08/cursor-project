import type { ValidatedTranscriptClaim } from "./analysis-schema";
import { automationHash } from "./idempotency";

export type ValidatedSourceAnalysis = Readonly<{
  analysisIdempotencyKey: string;
  videoId: string;
  characterId: string;
  claims: readonly ValidatedTranscriptClaim[];
}>;

export type MultiSourceMergeResult = Readonly<{
  status: "READY_TO_PUBLISH" | "BLOCKED";
  automaticPublishAllowed: false;
  sourceCount: number;
  mergedClaims: readonly ValidatedTranscriptClaim[];
  conflicts: readonly {
    claimKey: string;
    sourceAnalysisKeys: readonly string[];
  }[];
}>;

/**
 * Deterministic conflict detection is implemented now, but multi-source output
 * intentionally remains review-only until a later, separately validated phase.
 */
export function mergeValidatedSourceAnalyses(
  sources: readonly ValidatedSourceAnalysis[],
): MultiSourceMergeResult {
  const orderedSources = [...sources].sort((left, right) =>
    left.analysisIdempotencyKey.localeCompare(right.analysisIdempotencyKey),
  );
  if (orderedSources.length < 2) {
    return {
      status: "BLOCKED",
      automaticPublishAllowed: false,
      sourceCount: orderedSources.length,
      mergedClaims: [],
      conflicts: [],
    };
  }
  const characterIds = new Set(orderedSources.map((source) => source.characterId));
  if (characterIds.size !== 1) {
    return {
      status: "BLOCKED",
      automaticPublishAllowed: false,
      sourceCount: orderedSources.length,
      mergedClaims: [],
      conflicts: [
        {
          claimKey: "characterId",
          sourceAnalysisKeys: orderedSources.map(
            (source) => source.analysisIdempotencyKey,
          ),
        },
      ],
    };
  }
  const grouped = new Map<
    string,
    Array<{ sourceKey: string; claim: ValidatedTranscriptClaim }>
  >();
  for (const source of orderedSources) {
    for (const claim of source.claims) {
      const claimKey = automationHash("youtube-merged-claim-key-v1", {
        kind: claim.kind,
        entityId: claim.entityId,
        slot: claim.slot,
        condition: normalize(claim.condition),
      });
      const list = grouped.get(claimKey) ?? [];
      list.push({ sourceKey: source.analysisIdempotencyKey, claim });
      grouped.set(claimKey, list);
    }
  }
  const mergedClaims: ValidatedTranscriptClaim[] = [];
  const conflicts: MultiSourceMergeResult["conflicts"][number][] = [];
  for (const [claimKey, entries] of [...grouped].sort(([a], [b]) =>
    a.localeCompare(b),
  )) {
    const values = new Set(entries.map(({ claim }) => normalize(claim.value)));
    if (values.size > 1) {
      conflicts.push({
        claimKey,
        sourceAnalysisKeys: entries.map(({ sourceKey }) => sourceKey),
      });
      continue;
    }
    mergedClaims.push(
      [...entries]
        .sort(
          (left, right) =>
            right.claim.confidence - left.claim.confidence ||
            left.sourceKey.localeCompare(right.sourceKey),
        )[0]!.claim,
    );
  }
  return {
    status: conflicts.length > 0 ? "BLOCKED" : "READY_TO_PUBLISH",
    automaticPublishAllowed: false,
    sourceCount: orderedSources.length,
    mergedClaims,
    conflicts,
  };
}

function normalize(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase("ja");
}
