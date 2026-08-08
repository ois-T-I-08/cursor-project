import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  buildUncoveredEligibleQueue,
  computeCharacterCoverage,
  isCoveringRecommendationStatus,
  jobLooksLikePostProcessFailure,
  COVERAGE_RULE,
} from "../build-guides/visual-coverage";

vi.mock("@/lib/db", () => ({
  prisma: {
    character: { findMany: vi.fn() },
    characterBuildRecommendation: { findMany: vi.fn() },
    guideVideo: { findMany: vi.fn() },
    guideVisualAnalysisJob: { findMany: vi.fn() },
    guideVisualEvidence: { findMany: vi.fn() },
    recommendationVisualContribution: { findMany: vi.fn() },
    guideVisualExtractedClaim: { findMany: vi.fn() },
  },
}));

vi.mock("../build-guides/character-match", () => ({
  loadCharacterHints: vi.fn(async () => [
    { id: "c1", name: "モナ" },
    { id: "c2", name: "胡桃" },
    { id: "c3", name: "雷電将軍" },
  ]),
}));

const retryOnly = vi.fn();
vi.mock("../build-guides/visual-postprocess", () => ({
  retryVisualPostProcessOnly: (...args: unknown[]) => retryOnly(...args),
}));

describe("visual coverage hardening", () => {
  beforeEach(() => {
    retryOnly.mockReset();
  });

  it("documents covered rule and pending_review as covered; rejected not", () => {
    expect(COVERAGE_RULE).toContain("rejected");
    expect(isCoveringRecommendationStatus("pending_review")).toBe(true);
    expect(isCoveringRecommendationStatus("published")).toBe(true);
    expect(isCoveringRecommendationStatus("rejected")).toBe(false);
  });

  it("computeCharacterCoverage separates published vs pending_review; evidence-only not covered", () => {
    const result = computeCharacterCoverage({
      characters: [
        { id: "c1", name: "モナ" },
        { id: "c2", name: "胡桃" },
        { id: "c3", name: "雷電将軍" },
      ],
      recommendations: [
        { characterId: "c1", status: "published" },
        { characterId: "c2", status: "pending_review" },
        { characterId: "c3", status: "rejected" },
      ],
    });
    expect(result.coveredCharacters).toBe(2);
    expect(result.publishedCharacters).toBe(1);
    expect(result.pendingReviewCharacters).toBe(1);
    expect(result.uncoveredCharacters).toBe(1);
    expect(result.uncovered.map((c) => c.id)).toEqual(["c3"]);
  });

  it("jobLooksLikePostProcessFailure detects errorCode and rangesPayload", () => {
    expect(
      jobLooksLikePostProcessFailure({
        status: "succeeded",
        errorCode: "postProcess:mergeFailed",
      }),
    ).toBe(true);
    expect(
      jobLooksLikePostProcessFailure({
        status: "succeeded",
        errorCode: "",
        rangesPayload: JSON.stringify({
          postProcess: { status: "failed", code: "mergeFailed" },
        }),
      }),
    ).toBe(true);
    expect(
      jobLooksLikePostProcessFailure({
        status: "failed",
        errorCode: "analysisFailed",
      }),
    ).toBe(false);
    expect(
      jobLooksLikePostProcessFailure({
        status: "succeeded",
        errorCode: "",
        rangesPayload: "{}",
      }),
    ).toBe(false);
  });

  it("eligible queue=0 still allows master uncovered > 0 (metrics are separate)", () => {
    const char = computeCharacterCoverage({
      characters: [
        { id: "c1", name: "モナ" },
        { id: "c2", name: "胡桃" },
      ],
      recommendations: [],
    });
    expect(char.uncoveredCharacters).toBe(2);

    const queue = buildUncoveredEligibleQueue({
      pendingVideos: [
        {
          videoId: "aaaaaaaaaaa",
          title: "【原神】ガチャ優先度だけ語る動画",
        },
      ],
      hints: [
        { id: "c1", name: "モナ" },
        { id: "c2", name: "胡桃" },
      ],
      coveredIds: new Set(),
      limit: 3,
    });
    expect(queue.eligiblePendingVideos).toBe(0);
    expect(queue.remainingEligibleVideos).toBe(0);
    expect(queue.remainingEligibleVideos).not.toBe(char.uncoveredCharacters);
  });

  it("title resolution failures are counted separately (no AI resolve)", () => {
    const queue = buildUncoveredEligibleQueue({
      pendingVideos: [
        {
          videoId: "bbbbbbbbbbb",
          title:
            "【原神】「アリョーシャ」を引く人向けオススメ武器・聖遺物ガイド",
        },
        {
          videoId: "ccccccccccc",
          title: "【原神】「モナ」最新解説！おすすめ武器・聖遺物",
        },
      ],
      hints: [{ id: "c1", name: "モナ" }],
      coveredIds: new Set(),
      limit: 3,
    });
    expect(queue.titleResolutionFailedVideos).toBe(1);
    expect(queue.selected).toHaveLength(1);
    expect(queue.selected[0]?.characterId).toBe("c1");
  });

  it("recoverPostProcessFailures uses retry only (aiCalls=0) and maps success to covered", async () => {
    const { prisma } = await import("@/lib/db");
    const {
      recoverPostProcessFailures,
      listRecoverablePostProcessFailureVideoIds,
    } = await import("../build-guides/visual-coverage");

    vi.mocked(prisma.guideVisualAnalysisJob.findMany).mockResolvedValue([
      {
        videoId: "ddddddddddd",
        status: "succeeded",
        errorCode: "postProcess:mergeFailed",
        rangesPayload: JSON.stringify({
          postProcess: { status: "failed", code: "mergeFailed" },
        }),
        video: { analysisStatus: "analyzed", title: "t" },
      },
    ] as never);
    vi.mocked(prisma.guideVisualEvidence.findMany).mockResolvedValue([
      { videoId: "ddddddddddd" },
    ] as never);
    vi.mocked(prisma.recommendationVisualContribution.findMany).mockResolvedValue(
      [] as never,
    );

    const ids = await listRecoverablePostProcessFailureVideoIds(10);
    expect(ids).toEqual(["ddddddddddd"]);

    retryOnly.mockResolvedValue({
      recommendationIds: ["rec1"],
      attempts: 1,
      jobId: "job1",
    });

    vi.mocked(prisma.character.findMany).mockResolvedValue([
      { id: "c1", name: "モナ" },
    ] as never);
    // After recovery snapshot: pretend covered
    vi.mocked(prisma.characterBuildRecommendation.findMany).mockResolvedValue([
      { characterId: "c1", status: "pending_review" },
    ] as never);
    vi.mocked(prisma.guideVideo.findMany).mockResolvedValue([] as never);
    vi.mocked(prisma.guideVisualExtractedClaim.findMany).mockResolvedValue(
      [] as never,
    );

    const outcome = await recoverPostProcessFailures({ limit: 3 });
    expect(retryOnly).toHaveBeenCalledTimes(1);
    expect(retryOnly).toHaveBeenCalledWith("ddddddddddd");
    expect(outcome.aiCalls).toBe(0);
    expect(outcome.succeeded).toBe(1);
    expect(outcome.coverage.coveredCharacters).toBe(1);
  });

  it("failed recovery does not call Gemini (still aiCalls=0)", async () => {
    const { prisma } = await import("@/lib/db");
    const { recoverPostProcessFailures } = await import(
      "../build-guides/visual-coverage"
    );

    vi.mocked(prisma.guideVisualAnalysisJob.findMany).mockResolvedValue([
      {
        videoId: "eeeeeeeeeee",
        status: "succeeded",
        errorCode: "postProcess:mergeFailed",
        rangesPayload: "{}",
        video: { analysisStatus: "analyzed", title: "t" },
      },
    ] as never);
    vi.mocked(prisma.guideVisualEvidence.findMany).mockResolvedValue([
      { videoId: "eeeeeeeeeee" },
    ] as never);
    vi.mocked(prisma.recommendationVisualContribution.findMany).mockResolvedValue(
      [] as never,
    );
    retryOnly.mockRejectedValue(Object.assign(new Error("mergeFailed"), { code: "mergeFailed" }));

    vi.mocked(prisma.character.findMany).mockResolvedValue([
      { id: "c1", name: "モナ" },
    ] as never);
    vi.mocked(prisma.characterBuildRecommendation.findMany).mockResolvedValue(
      [] as never,
    );
    vi.mocked(prisma.guideVideo.findMany).mockResolvedValue([] as never);
    vi.mocked(prisma.guideVisualExtractedClaim.findMany).mockResolvedValue(
      [] as never,
    );

    const outcome = await recoverPostProcessFailures({ limit: 1 });
    expect(outcome.aiCalls).toBe(0);
    expect(outcome.failed).toBe(1);
    expect(outcome.succeeded).toBe(0);
    expect(retryOnly).toHaveBeenCalledTimes(1);
  });

  it("videos with recommendation contribution are not recoverable", async () => {
    const { prisma } = await import("@/lib/db");
    const { listRecoverablePostProcessFailureVideoIds } = await import(
      "../build-guides/visual-coverage"
    );
    vi.mocked(prisma.guideVisualAnalysisJob.findMany).mockResolvedValue([
      {
        videoId: "fffffffffff",
        status: "succeeded",
        errorCode: "postProcess:mergeFailed",
        rangesPayload: "{}",
        video: { analysisStatus: "analyzed", title: "t" },
      },
    ] as never);
    vi.mocked(prisma.guideVisualEvidence.findMany).mockResolvedValue([
      { videoId: "fffffffffff" },
    ] as never);
    vi.mocked(prisma.recommendationVisualContribution.findMany).mockResolvedValue(
      [{ videoId: "fffffffffff" }] as never,
    );
    await expect(listRecoverablePostProcessFailureVideoIds(10)).resolves.toEqual(
      [],
    );
  });
});
