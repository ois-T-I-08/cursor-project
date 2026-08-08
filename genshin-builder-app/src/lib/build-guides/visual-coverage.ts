import "server-only";

import { prisma } from "@/lib/db";
import {
  isCharacterBuildGuideTitle,
  resolvePrimaryCharacterFromTitle,
  type CharacterHint,
} from "./character-match-logic";
import { loadCharacterHints } from "./character-match";
import { GENSIN_VIDEO_TITLE_MARKER } from "./genshin-video-title";
import { retryVisualPostProcessOnly } from "./visual-postprocess";

/**
 * Covered = CharacterBuildRecommendation exists with status != "rejected".
 * pending_review counts as covered (unchanged policy); published is reported separately.
 */
export const COVERAGE_RULE =
  "CharacterBuildRecommendation.status != 'rejected' (pending_review counts; publish not required; jobs/evidence alone do not cover)";

export type CoverageMetrics = {
  /** Explicit rule for admins / API consumers */
  coverageRule: typeof COVERAGE_RULE;
  totalCharacters: number;
  coveredCharacters: number;
  uncoveredCharacters: number;
  publishedCharacters: number;
  pendingReviewCharacters: number;
  evidenceOnlyCharacters: number;
  recoverablePostProcessFailures: number;
  eligiblePendingVideos: number;
  remainingEligibleVideos: number;
  titleResolutionFailedVideos: number;
  uncoveredCharacterNames: string[];
  recoverableVideoIds: string[];
  titleResolutionFailedSamples: string[];
};

export type CoverageCharacterRow = {
  id: string;
  name: string;
};

export type CoverageRecommendationRow = {
  characterId: string;
  status: string;
};

export function isCoveringRecommendationStatus(status: string): boolean {
  return status !== "rejected";
}

/** Pure: compute character-level coverage from master + recommendation rows. */
export function computeCharacterCoverage(input: {
  characters: CoverageCharacterRow[];
  recommendations: CoverageRecommendationRow[];
}): {
  coveredIds: Set<string>;
  publishedIds: Set<string>;
  pendingReviewIds: Set<string>;
  uncovered: CoverageCharacterRow[];
  totalCharacters: number;
  coveredCharacters: number;
  uncoveredCharacters: number;
  publishedCharacters: number;
  pendingReviewCharacters: number;
} {
  const coveredIds = new Set<string>();
  const publishedIds = new Set<string>();
  const pendingReviewIds = new Set<string>();
  for (const row of input.recommendations) {
    if (!isCoveringRecommendationStatus(row.status)) continue;
    coveredIds.add(row.characterId);
    if (row.status === "published") publishedIds.add(row.characterId);
    if (row.status === "pending_review") pendingReviewIds.add(row.characterId);
  }
  const uncovered = input.characters.filter((c) => !coveredIds.has(c.id));
  return {
    coveredIds,
    publishedIds,
    pendingReviewIds,
    uncovered,
    totalCharacters: input.characters.length,
    coveredCharacters: coveredIds.size,
    uncoveredCharacters: uncovered.length,
    publishedCharacters: publishedIds.size,
    pendingReviewCharacters: pendingReviewIds.size,
  };
}

export function jobLooksLikePostProcessFailure(job: {
  status: string;
  errorCode: string;
  rangesPayload?: string;
}): boolean {
  if (job.status !== "succeeded") return false;
  if (job.errorCode.startsWith("postProcess:")) return true;
  try {
    const ranges = JSON.parse(job.rangesPayload || "{}") as {
      postProcess?: { status?: string };
    };
    return ranges.postProcess?.status === "failed";
  } catch {
    return false;
  }
}

/** Pure eligibility for uncoveredCharacters AI queue (Gemini). */
export function buildUncoveredEligibleQueue(input: {
  pendingVideos: Array<{ videoId: string; title: string }>;
  hints: CharacterHint[];
  coveredIds: Set<string>;
  limit: number;
}): {
  selected: Array<{ videoId: string; title: string; characterId: string }>;
  eligiblePendingVideos: number;
  remainingEligibleVideos: number;
  titleResolutionFailedVideos: number;
  titleResolutionFailedSamples: string[];
  skippedNotGuide: number;
  skippedCovered: number;
} {
  const claimed = new Set(input.coveredIds);
  const queue: Array<{ videoId: string; title: string; characterId: string }> =
    [];
  let titleResolutionFailedVideos = 0;
  const titleResolutionFailedSamples: string[] = [];
  let skippedNotGuide = 0;
  let skippedCovered = 0;

  for (const video of input.pendingVideos) {
    if (!isCharacterBuildGuideTitle(video.title)) {
      skippedNotGuide += 1;
      continue;
    }
    const characterId = resolvePrimaryCharacterFromTitle(video.title, input.hints);
    if (!characterId) {
      titleResolutionFailedVideos += 1;
      if (titleResolutionFailedSamples.length < 20) {
        titleResolutionFailedSamples.push(video.title);
      }
      continue;
    }
    if (claimed.has(characterId)) {
      skippedCovered += 1;
      continue;
    }
    claimed.add(characterId);
    queue.push({ ...video, characterId });
  }

  const limit = Math.max(0, input.limit);
  return {
    selected: queue.slice(0, limit),
    eligiblePendingVideos: queue.length,
    remainingEligibleVideos: Math.max(0, queue.length - limit),
    titleResolutionFailedVideos,
    titleResolutionFailedSamples,
    skippedNotGuide,
    skippedCovered,
  };
}

async function loadCoveringRecommendations(): Promise<
  CoverageRecommendationRow[]
> {
  return prisma.characterBuildRecommendation.findMany({
    where: { status: { not: "rejected" } },
    select: { characterId: true, status: true },
  });
}

/** Videos: Gemini succeeded, postProcess failed, validated evidence exists, no non-rejected rec from this video. */
export async function listRecoverablePostProcessFailureVideoIds(
  take = 100,
): Promise<string[]> {
  const jobs = await prisma.guideVisualAnalysisJob.findMany({
    where: {
      status: "succeeded",
      OR: [
        { errorCode: { startsWith: "postProcess:" } },
        { rangesPayload: { contains: '"status":"failed"' } },
      ],
    },
    orderBy: { completedAt: "desc" },
    take: Math.min(Math.max(take, 1), 200),
    select: {
      videoId: true,
      status: true,
      errorCode: true,
      rangesPayload: true,
      video: { select: { analysisStatus: true, title: true } },
    },
  });

  const candidates = jobs.filter(
    (j) =>
      jobLooksLikePostProcessFailure(j) &&
      j.video.analysisStatus === "analyzed",
  );
  if (candidates.length === 0) return [];

  const videoIds = [...new Set(candidates.map((j) => j.videoId))];

  const [evidences, contributions] = await Promise.all([
    prisma.guideVisualEvidence.findMany({
      where: {
        videoId: { in: videoIds },
        validationStatus: "validated",
        approvalStatus: { not: "rejected" },
      },
      distinct: ["videoId"],
      select: { videoId: true },
    }),
    prisma.recommendationVisualContribution.findMany({
      where: {
        videoId: { in: videoIds },
        recommendation: { status: { not: "rejected" } },
      },
      distinct: ["videoId"],
      select: { videoId: true },
    }),
  ]);

  const hasEvidence = new Set(evidences.map((e) => e.videoId));
  const hasRec = new Set(contributions.map((c) => c.videoId));
  return videoIds.filter((id) => hasEvidence.has(id) && !hasRec.has(id));
}

export async function getCoverageMetrics(input?: {
  /** Limit used for remainingEligibleVideos (= eligible - limit). */
  eligibleLimit?: number;
}): Promise<CoverageMetrics> {
  const eligibleLimit = Math.min(Math.max(input?.eligibleLimit ?? 3, 1), 10);
  const hints = await loadCharacterHints();
  const recommendations = await loadCoveringRecommendations();
  const charCov = computeCharacterCoverage({
    characters: hints,
    recommendations,
  });

  const pendingVideos = await prisma.guideVideo.findMany({
    where: {
      title: { contains: GENSIN_VIDEO_TITLE_MARKER },
      analysisStatus: { not: "analyzed" },
      privacyStatus: "public",
      channel: {
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    },
    orderBy: [{ publishedAt: "desc" }, { updatedAt: "desc" }],
    take: 500,
    select: { videoId: true, title: true },
  });

  const eligible = buildUncoveredEligibleQueue({
    pendingVideos,
    hints,
    coveredIds: charCov.coveredIds,
    limit: eligibleLimit,
  });

  const recoverableVideoIds =
    await listRecoverablePostProcessFailureVideoIds(100);

  // Evidence-only: validated evidence for a character, but character not covered.
  const claims = await prisma.guideVisualExtractedClaim.findMany({
    distinct: ["characterId"],
    select: { characterId: true },
  });
  const evidenceOnlyCharacters = claims.filter(
    (c) =>
      typeof c.characterId === "string" &&
      c.characterId.length > 0 &&
      !charCov.coveredIds.has(c.characterId),
  ).length;

  return {
    coverageRule: COVERAGE_RULE,
    totalCharacters: charCov.totalCharacters,
    coveredCharacters: charCov.coveredCharacters,
    uncoveredCharacters: charCov.uncoveredCharacters,
    publishedCharacters: charCov.publishedCharacters,
    pendingReviewCharacters: charCov.pendingReviewCharacters,
    evidenceOnlyCharacters,
    recoverablePostProcessFailures: recoverableVideoIds.length,
    eligiblePendingVideos: eligible.eligiblePendingVideos,
    remainingEligibleVideos: eligible.remainingEligibleVideos,
    titleResolutionFailedVideos: eligible.titleResolutionFailedVideos,
    uncoveredCharacterNames: charCov.uncovered.map((c) => c.name),
    recoverableVideoIds,
    titleResolutionFailedSamples: eligible.titleResolutionFailedSamples,
  };
}

/**
 * Recover postProcess failures via deterministic retry only — never calls Gemini.
 * Limit capped to avoid mass batch.
 */
export async function recoverPostProcessFailures(input: {
  limit?: number;
} = {}): Promise<{
  attempted: number;
  succeeded: number;
  failed: number;
  results: Array<{
    videoId: string;
    ok: boolean;
    recommendationIds?: string[];
    error?: string;
  }>;
  coverage: CoverageMetrics;
  note: string;
  aiCalls: 0;
}> {
  const limit = Math.min(Math.max(input.limit ?? 3, 1), 5);
  const videoIds = (
    await listRecoverablePostProcessFailureVideoIds(limit)
  ).slice(0, limit);

  const results: Array<{
    videoId: string;
    ok: boolean;
    recommendationIds?: string[];
    error?: string;
  }> = [];

  for (const videoId of videoIds) {
    try {
      const outcome = await retryVisualPostProcessOnly(videoId);
      results.push({
        videoId,
        ok: true,
        recommendationIds: outcome.recommendationIds,
      });
    } catch (error) {
      const code =
        error instanceof Error && "code" in error
          ? String((error as { code?: unknown }).code ?? error.message)
          : error instanceof Error
            ? error.message
            : "recoveryFailed";
      results.push({ videoId, ok: false, error: code });
    }
  }

  const coverage = await getCoverageMetrics({ eligibleLimit: limit });
  return {
    attempted: results.length,
    succeeded: results.filter((r) => r.ok).length,
    failed: results.filter((r) => !r.ok).length,
    results,
    coverage,
    aiCalls: 0,
    note:
      results.length === 0
        ? "復旧対象の postProcess 失敗はありませんでした（AI再解析は行いません）。"
        : "validated evidence から postProcess のみ再実行しました。Gemini 再課金はありません。",
  };
}
