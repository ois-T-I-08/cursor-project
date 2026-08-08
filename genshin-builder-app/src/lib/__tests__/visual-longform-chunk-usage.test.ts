import { describe, expect, it } from "vitest";
import {
  buildLongformChunkUsageRecord,
  extractLongformChunkUsage,
  readActualTokenCountsFromUsage,
} from "../build-guides/visual-longform";

describe("longform chunk usage observability", () => {
  it("reads actual token counters without inventing from estimates", () => {
    expect(readActualTokenCountsFromUsage(undefined)).toEqual({
      actualPromptTokens: null,
      actualCandidateTokens: null,
      actualTotalTokens: null,
    });
    expect(
      readActualTokenCountsFromUsage({
        promptTokenCount: 1200,
        candidatesTokenCount: 80,
        totalTokenCount: 1280,
        longformChunks: 3,
      }),
    ).toEqual({
      actualPromptTokens: 1200,
      actualCandidateTokens: 80,
      actualTotalTokens: 1280,
    });
  });

  it("cacheHit forces actual tokens null even if usage is provided", () => {
    const record = buildLongformChunkUsageRecord({
      chunkIndex: 1,
      rangeStart: 348,
      rangeEnd: 708,
      estimatedTokens: 35_128,
      usage: {
        promptTokenCount: 99_999,
        candidatesTokenCount: 1,
        totalTokenCount: 100_000,
      },
      attempts: 2,
      cacheHit: true,
      provider: "gemini-youtube-visual",
      requestHash: "abc123def",
    });
    expect(record.cacheHit).toBe(true);
    expect(record.actualPromptTokens).toBeNull();
    expect(record.actualCandidateTokens).toBeNull();
    expect(record.actualTotalTokens).toBeNull();
    expect(record.attempts).toBe(0);
    expect(record.retryCount).toBe(0);
    expect(record.estimatedTokens).toBe(35_128);
    expect(record.requestHash).toBe("abc123def");
  });

  it("paid call records actual tokens and retryCount = attempts - 1", () => {
    const record = buildLongformChunkUsageRecord({
      chunkIndex: 0,
      rangeStart: 0,
      rangeEnd: 360,
      estimatedTokens: 35_128,
      usage: {
        promptTokenCount: 30_100,
        candidatesTokenCount: 900,
        totalTokenCount: 31_000,
      },
      attempts: 3,
      cacheHit: false,
      provider: "gemini-youtube-visual",
      requestHash: "deadbeef01",
    });
    expect(record).toMatchObject({
      chunkIndex: 0,
      rangeStart: 0,
      rangeEnd: 360,
      estimatedTokens: 35_128,
      actualPromptTokens: 30_100,
      actualCandidateTokens: 900,
      actualTotalTokens: 31_000,
      attempts: 3,
      retryCount: 2,
      cacheHit: false,
      provider: "gemini-youtube-visual",
      requestHash: "deadbeef01",
    });
  });

  it("never copies estimatedTokens into actual* when usage missing", () => {
    const record = buildLongformChunkUsageRecord({
      chunkIndex: 2,
      rangeStart: 696,
      rangeEnd: 1011,
      estimatedTokens: 30_988,
      usage: null,
      attempts: 0,
      cacheHit: false,
      provider: "gemini-youtube-visual",
      requestHash: "cafe0123",
    });
    expect(record.actualPromptTokens).toBeNull();
    expect(record.actualCandidateTokens).toBeNull();
    expect(record.actualTotalTokens).toBeNull();
    expect(record.actualPromptTokens).not.toBe(record.estimatedTokens);
  });

  it("strips non-hex noise from requestHash (no prompt/secret leakage)", () => {
    const record = buildLongformChunkUsageRecord({
      chunkIndex: 0,
      rangeStart: 0,
      rangeEnd: 10,
      estimatedTokens: 100,
      cacheHit: true,
      provider: "gemini-youtube-visual",
      requestHash: "ab!!cd\nEF12;sk-secret",
    });
    // Non-hex stripped (keeps remaining hex chars only; never keeps separators / sk- prefix).
    expect(record.requestHash).toBe("abcdEF12ece");
    expect(record.requestHash).not.toContain("sk-");
    expect(record.requestHash).not.toContain(";");
    expect(record.requestHash).not.toContain("\n");
  });

  it("extracts chunkUsage from rangesPayload top-level or longform nested", () => {
    const payload = {
      analysisMode: "longform_chunked",
      longform: {
        status: "complete",
        chunkUsage: [
          {
            chunkIndex: 1,
            rangeStart: 348,
            rangeEnd: 708,
            estimatedTokens: 35128,
            actualPromptTokens: 30000,
            actualCandidateTokens: 1000,
            actualTotalTokens: 31000,
            attempts: 1,
            retryCount: 0,
            cacheHit: false,
            provider: "gemini-youtube-visual",
            requestHash: "bbbb",
          },
        ],
      },
      chunkUsage: [
        {
          chunkIndex: 0,
          rangeStart: 0,
          rangeEnd: 360,
          estimatedTokens: 35128,
          actualPromptTokens: null,
          actualCandidateTokens: null,
          actualTotalTokens: null,
          attempts: 0,
          retryCount: 0,
          cacheHit: true,
          provider: "gemini-youtube-visual",
          requestHash: "aaaa",
        },
        {
          chunkIndex: 1,
          rangeStart: 348,
          rangeEnd: 708,
          estimatedTokens: 35128,
          actualPromptTokens: 30000,
          actualCandidateTokens: 1000,
          actualTotalTokens: 31000,
          attempts: 1,
          retryCount: 0,
          cacheHit: false,
          provider: "gemini-youtube-visual",
          requestHash: "bbbb",
        },
      ],
    };
    const extracted = extractLongformChunkUsage(JSON.stringify(payload));
    expect(extracted).toHaveLength(2);
    expect(extracted[0]?.cacheHit).toBe(true);
    expect(extracted[0]?.actualTotalTokens).toBeNull();
    expect(extracted[1]?.actualTotalTokens).toBe(31_000);
  });

  it("legacy rangesPayload without chunkUsage returns empty (no backfill)", () => {
    const legacy = {
      analysisMode: "longform_chunked",
      longform: {
        status: "complete",
        completedChunkIndexes: [0, 1, 2],
      },
      plan: {
        chunkCount: 3,
        chunks: [
          { i: 0, s: 0, e: 360, tokens: 35128 },
          { i: 1, s: 348, e: 708, tokens: 35128 },
          { i: 2, s: 696, e: 1011, tokens: 30988 },
        ],
      },
    };
    expect(extractLongformChunkUsage(JSON.stringify(legacy))).toEqual([]);
    expect(extractLongformChunkUsage(null)).toEqual([]);
    expect(extractLongformChunkUsage("{not-json")).toEqual([]);
  });
});
