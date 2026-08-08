import { describe, expect, it, vi } from "vitest";
import {
  assertVisualTokenBudget,
  VISUAL_PROMPT_TOKEN_HARD_MAX,
} from "../build-guides/visual-analysis-safety";
import {
  assertLongformCostGuard,
  buildLongformPartialState,
  computeLongformChunkSeconds,
  estimateMergeTokens,
  isLongformPublishable,
  LONGFORM_CHUNK_TOKEN_TARGET,
  LONGFORM_MAX_CHUNKS,
  LONGFORM_OVERLAP_SECONDS,
  LongformPlanningError,
  mergeLongformChunkResults,
  needsLongformFullDiscovery,
  planLongformChunks,
  reduceLongformChunkResults,
} from "../build-guides/visual-longform";
import type { VideoVisualAnalysisResult } from "../build-guides/visual-schemas";

function evidence(
  videoId: string,
  start: number,
  end: number,
  text: string,
  characterId = "mavuika",
): VideoVisualAnalysisResult["evidences"][number] {
  return {
    videoId,
    startSeconds: start,
    endSeconds: end,
    evidenceType: "recommendation_table",
    targetCharacterIds: [characterId],
    visibleTexts: [{ text, confidence: 0.9, category: "other" }],
    statValues: [],
    recommendedMainStats: null,
    statPriority: ["critRate"],
    weaponMentions: [],
    artifactSetMentions: [],
    visualSummary: text,
    confidence: 0.9,
    readable: true,
    warnings: [],
  };
}

function chunkResult(
  videoId: string,
  start: number,
  end: number,
  text: string,
): VideoVisualAnalysisResult {
  return {
    videoId,
    relevant: true,
    detectedCharacterIds: ["mavuika"],
    evidences: [evidence(videoId, start, end, text)],
    unresolvedEntities: [],
    analysisSummary: text,
  };
}

describe("visual long-form hardening", () => {
  it("<80k stays on conventional full_discovery path (no longform needed)", () => {
    expect(
      needsLongformFullDiscovery({
        durationSeconds: 120,
        fps: 1,
        targetCharacterCount: 1,
      }),
    ).toBe(false);
    expect(
      assertVisualTokenBudget({
        durationSeconds: 120,
        fps: 1,
        analysisMode: "full_discovery",
        targetCharacterCount: 1,
      }).estimatedTokens,
    ).toBeLessThan(VISUAL_PROMPT_TOKEN_HARD_MAX);
  });

  it(">80k routes to longform planning (hard max not raised)", () => {
    expect(
      needsLongformFullDiscovery({
        durationSeconds: 1_198,
        fps: 1,
        targetCharacterCount: 1,
      }),
    ).toBe(true);
    expect(() =>
      assertVisualTokenBudget({
        durationSeconds: 1_198,
        fps: 1,
        analysisMode: "full_discovery",
        targetCharacterCount: 1,
      }),
    ).toThrow(/videoTooLargeForFullDiscovery/);

    const plan = planLongformChunks({
      videoId: "longformvid01",
      durationSeconds: 1_198,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    expect(plan.chunks.length).toBeGreaterThan(1);
    expect(plan.chunks.length).toBeLessThanOrEqual(LONGFORM_MAX_CHUNKS);
    for (const chunk of plan.chunks) {
      expect(chunk.estimatedTokens).toBeLessThanOrEqual(
        VISUAL_PROMPT_TOKEN_HARD_MAX,
      );
      expect(chunk.estimatedTokens).toBeLessThanOrEqual(
        LONGFORM_CHUNK_TOKEN_TARGET + 5_000,
      );
      expect(chunk.endSeconds - chunk.startSeconds).toBeLessThanOrEqual(180);
    }
  });

  it("chunk boundaries use timestamp steps + overlap headroom", () => {
    const chunkSeconds = computeLongformChunkSeconds({
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    expect(chunkSeconds).toBeLessThanOrEqual(180);
    const plan = planLongformChunks({
      videoId: "longformvid02",
      durationSeconds: 600,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
      overlapSeconds: LONGFORM_OVERLAP_SECONDS,
      boundaryHints: [180, 360],
    });
    expect(plan.overlapSeconds).toBe(LONGFORM_OVERLAP_SECONDS);
    // Adjacent chunks overlap (except last start).
    for (let i = 1; i < plan.chunks.length; i++) {
      const prev = plan.chunks[i - 1]!;
      const cur = plan.chunks[i]!;
      expect(cur.startSeconds).toBeLessThan(prev.endSeconds);
      expect(prev.endSeconds - cur.startSeconds).toBeLessThanOrEqual(
        LONGFORM_OVERLAP_SECONDS + 1,
      );
    }
  });

  it("merge dedupes overlapping identical evidences and keeps conflicts", () => {
    const videoId = "longformvid03";
    const a = chunkResult(videoId, 0, 180, "ER 140");
    const b = chunkResult(videoId, 168, 348, "ER 140"); // overlap duplicate
    const c = chunkResult(videoId, 336, 516, "ER 180"); // conflicting text
    const merged = mergeLongformChunkResults(videoId, [
      { chunkIndex: 0, result: a },
      { chunkIndex: 1, result: b },
      { chunkIndex: 2, result: c },
    ]);
    expect(merged.evidences).toHaveLength(2);
    expect(merged.evidences.map((e) => e.visibleTexts[0]?.text)).toEqual([
      "ER 140",
      "ER 180",
    ]);
  });

  it("merge token guard uses hierarchical reduce", () => {
    const videoId = "longformvid04";
    const chunks = Array.from({ length: 12 }, (_, i) => ({
      chunkIndex: i,
      result: chunkResult(
        videoId,
        i * 100,
        i * 100 + 90,
        `slice-${i}-${"x".repeat(200)}`,
      ),
    }));
    const directTokens = estimateMergeTokens(chunks.map((c) => c.result));
    const reduced = reduceLongformChunkResults(videoId, chunks, 3);
    expect(reduced.levels).toBeGreaterThanOrEqual(1);
    expect(reduced.result.evidences.length).toBeGreaterThan(0);
    // Reduce should not explode merge estimate beyond a soft bound for tiny fixtures.
    expect(reduced.estimatedMergeTokens).toBeLessThanOrEqual(
      Math.max(directTokens, 40_000),
    );
  });

  it("partial chunk failure is not publishable; resume keeps completed indexes", () => {
    const plan = planLongformChunks({
      videoId: "longformvid05",
      durationSeconds: 600,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    const partial = buildLongformPartialState({
      plan,
      completedChunkIndexes: [0, 1],
      failedChunkIndex: 2,
      failedCode: "http500",
    });
    expect(partial.status).toBe("partial");
    expect(isLongformPublishable(partial)).toBe(false);
    expect(partial.completedChunkIndexes).toEqual([0, 1]);
  });

  it("Emergency mid-pipeline aborts without publish", () => {
    const plan = planLongformChunks({
      videoId: "longformvid06",
      durationSeconds: 400,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    const state = buildLongformPartialState({
      plan,
      completedChunkIndexes: [0],
      failedChunkIndex: 1,
      emergency: true,
    });
    expect(state.status).toBe("aborted_emergency");
    expect(isLongformPublishable(state)).toBe(false);
  });

  it("429 / rate-limit aborts remaining chunks", () => {
    const plan = planLongformChunks({
      videoId: "longformvid07",
      durationSeconds: 400,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    const state = buildLongformPartialState({
      plan,
      completedChunkIndexes: [0],
      failedChunkIndex: 1,
      failedCode: "http429",
      rateLimited: true,
    });
    expect(state.status).toBe("aborted_rate_limit");
    expect(isLongformPublishable(state)).toBe(false);
  });

  it("huge chunk count cost guard refuses to start", () => {
    expect(() =>
      assertLongformCostGuard({
        version: "v1",
        durationSeconds: 99_999,
        fps: 1,
        chunkSeconds: 30,
        overlapSeconds: 0,
        chunks: Array.from({ length: LONGFORM_MAX_CHUNKS + 1 }, (_, i) => ({
          chunkIndex: i,
          startSeconds: i * 30,
          endSeconds: i * 30 + 30,
          reason: "x",
          estimatedTokens: 1_000,
          chunkKey: `k${i}`,
        })),
        estimatedInputTokens: 1_000_000,
        estimatedAiCalls: LONGFORM_MAX_CHUNKS + 1,
      }),
    ).toThrow(LongformPlanningError);
  });

  it("chunk visual ranges never cover full video duration in one call", () => {
    const plan = planLongformChunks({
      videoId: "longformvid08",
      durationSeconds: 1_198,
      fps: 1,
      targetCharacterCount: 1,
      maxRangeSeconds: 180,
    });
    for (const chunk of plan.chunks) {
      expect(chunk.endSeconds - chunk.startSeconds).toBeLessThan(1_198);
      expect(chunk.endSeconds - chunk.startSeconds).toBeLessThanOrEqual(180);
    }
  });

  it("stable chunk keys support resume/cache identity", () => {
    const planA = planLongformChunks({
      videoId: "longformvid09",
      durationSeconds: 500,
      fps: 1,
      targetCharacterCount: 2,
      maxRangeSeconds: 180,
    });
    const planB = planLongformChunks({
      videoId: "longformvid09",
      durationSeconds: 500,
      fps: 1,
      targetCharacterCount: 2,
      maxRangeSeconds: 180,
    });
    expect(planA.chunks.map((c) => c.chunkKey)).toEqual(
      planB.chunks.map((c) => c.chunkKey),
    );
  });
});

describe("longform + emergency gate contract (no real AI)", () => {
  it("does not start merge when incomplete", () => {
    const publish = vi.fn();
    const state = buildLongformPartialState({
      plan: planLongformChunks({
        videoId: "longformvid10",
        durationSeconds: 500,
        fps: 1,
        targetCharacterCount: 1,
        maxRangeSeconds: 180,
      }),
      completedChunkIndexes: [0],
      failedChunkIndex: 1,
      failedCode: "timeout",
    });
    if (!isLongformPublishable(state)) {
      // merge/publish skipped
    } else {
      publish();
    }
    expect(publish).not.toHaveBeenCalled();
  });
});
