import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  evaluateLimitedBatchEligibility,
  LIMITED_BATCH_CANARY_CONCURRENCY,
  LIMITED_BATCH_CANARY_MAX_ITEMS,
  LimitedBatchCanaryError,
  runLimitedBatchCanary,
  shouldAbortLimitedBatchCanary,
  type LimitedBatchCanaryDeps,
} from "../build-guides/limited-batch-canary";
import { GuideVisualAnalysisError } from "../build-guides/visual-analysis-service";

const HINTS = [{ id: "char_a", name: "ノエル" }, { id: "char_b", name: "フィッシュル" }, { id: "char_c", name: "ベネット" }];

function guideTitle(name: string) {
  return `【原神】${name}最新育成ガイド！おすすめ武器・聖遺物・目標ステータス【げんしん】`;
}

function videoRow(
  videoId: string,
  name: string,
  overrides: Partial<{
    analysisStatus: string;
    privacyStatus: string;
    durationSeconds: number;
    channelEnabled: boolean;
    permissionStatus: string;
  }> = {},
) {
  return {
    videoId,
    title: guideTitle(name),
    privacyStatus: overrides.privacyStatus ?? "public",
    analysisStatus: overrides.analysisStatus ?? "pending",
    durationSeconds: overrides.durationSeconds ?? 600,
    metadataHash: `meta-${videoId}`,
    publishedAt: new Date("2026-01-01T00:00:00Z"),
    channel: {
      enabled: overrides.channelEnabled ?? true,
      permissionStatus: overrides.permissionStatus ?? "approved_for_processing",
    },
  };
}

function baseDeps(overrides: Partial<LimitedBatchCanaryDeps> = {}): LimitedBatchCanaryDeps {
  const videos = new Map([
    ["vidAAAAAAA1", videoRow("vidAAAAAAA1", "ノエル")],
    ["vidBBBBBBB2", videoRow("vidBBBBBBB2", "フィッシュル")],
    ["vidCCCCCCC3", videoRow("vidCCCCCCC3", "ベネット")],
  ]);
  const analyze = vi.fn(async (input: { videoId: string }) => ({
    status: "validated",
    providerCalls: 1,
    retries: 0,
    cacheHit: false,
    publishDelta: 0,
    recommendationIds: [`rec-${input.videoId}`],
  }));

  return {
    readEmergency: async () => ({ emergencyStopped: false, version: 18 }),
    assertProviderNotCoolingDown: () => undefined,
    getProviderCooldownRemainingMs: () => 0,
    loadHints: async () => HINTS,
    loadCoveredCharacterIds: async () => new Set(),
    loadVideo: async (id) => videos.get(id) ?? null,
    countRunningJobs: async () => 0,
    countRecent429: async () => 0,
    hasValidatedCache: async () => false,
    analyze,
    ...overrides,
  };
}

describe("shouldAbortLimitedBatchCanary", () => {
  it("aborts on 429 / cooldown / emergency / unexpected publish", () => {
    expect(shouldAbortLimitedBatchCanary("http429")).toBe(true);
    expect(shouldAbortLimitedBatchCanary("providerRateLimited")).toBe(true);
    expect(shouldAbortLimitedBatchCanary("geminiProviderCoolingDown")).toBe(
      true,
    );
    expect(shouldAbortLimitedBatchCanary("emergencyStopped")).toBe(true);
    expect(shouldAbortLimitedBatchCanary("unexpectedPublish")).toBe(true);
    expect(shouldAbortLimitedBatchCanary("invalidJson")).toBe(false);
  });
});

describe("evaluateLimitedBatchEligibility", () => {
  it("rejects analyzed / covered / non-guide / running / recent429 / cache", () => {
    const base = {
      hints: HINTS,
      coveredIds: new Set<string>(),
      runningJobs: 0,
      recent429: 0,
      providerCoolingDown: false,
      cacheHit: false,
      video: videoRow("vidAAAAAAA1", "ノエル"),
    };
    expect(
      evaluateLimitedBatchEligibility({
        ...base,
        video: videoRow("vidAAAAAAA1", "ノエル", { analysisStatus: "analyzed" }),
      }).ok,
    ).toBe(false);
    expect(
      evaluateLimitedBatchEligibility({
        ...base,
        coveredIds: new Set(["char_a"]),
      }).ok,
    ).toBe(false);
    expect(
      evaluateLimitedBatchEligibility({
        ...base,
        video: {
          ...videoRow("vidAAAAAAA1", "ノエル"),
          title: "【原神】ガチャ優先度まとめ",
        },
      }).ok,
    ).toBe(false);
    expect(
      evaluateLimitedBatchEligibility({ ...base, runningJobs: 1 }).ok,
    ).toBe(false);
    expect(evaluateLimitedBatchEligibility({ ...base, recent429: 1 }).ok).toBe(
      false,
    );
    expect(evaluateLimitedBatchEligibility({ ...base, cacheHit: true }).ok).toBe(
      false,
    );
  });

  it("marks longform for >80k full discovery estimate", () => {
    const result = evaluateLimitedBatchEligibility({
      hints: HINTS,
      coveredIds: new Set(),
      runningJobs: 0,
      recent429: 0,
      providerCoolingDown: false,
      cacheHit: false,
      video: videoRow("vidAAAAAAA1", "ノエル", { durationSeconds: 1100 }),
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.longform).toBe(true);
  });
});

describe("runLimitedBatchCanary", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("A: 3 items sequential success, concurrency=1, attempted=3", async () => {
    const order: string[] = [];
    const analyze = vi.fn(async (input: { videoId: string }) => {
      order.push(input.videoId);
      return {
        status: "validated",
        providerCalls: 1,
        retries: 0,
        cacheHit: false,
        publishDelta: 0,
      };
    });
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"],
      deps: baseDeps({ analyze }),
    });
    expect(result.concurrency).toBe(LIMITED_BATCH_CANARY_CONCURRENCY);
    expect(result.maxItems).toBe(LIMITED_BATCH_CANARY_MAX_ITEMS);
    expect(result.force).toBe(false);
    expect(result.skipAutoPublish).toBe(true);
    expect(result.attempted).toBe(3);
    expect(result.succeeded).toBe(3);
    expect(result.aborted).toBe(false);
    expect(order).toEqual(["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"]);
    expect(analyze).toHaveBeenCalledTimes(3);
  });

  it("B: item1 http429 aborts — item2/3 never analyzed", async () => {
    const analyze = vi.fn(async (input: { videoId: string }) => {
      if (input.videoId === "vidAAAAAAA1") {
        throw new GuideVisualAnalysisError("http429");
      }
      return {
        status: "validated",
        providerCalls: 1,
        retries: 0,
        cacheHit: false,
        publishDelta: 0,
      };
    });
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"],
      deps: baseDeps({ analyze }),
    });
    expect(result.aborted).toBe(true);
    expect(result.abortCode).toBe("http429");
    expect(result.http429).toBe(1);
    expect(result.attempted).toBe(1);
    expect(analyze).toHaveBeenCalledTimes(1);
    expect(result.items[1]?.status).toBe("aborted_before_start");
    expect(result.items[2]?.status).toBe("aborted_before_start");
    expect(result.remainingItems).toEqual(["vidBBBBBBB2", "vidCCCCCCC3"]);
  });

  it("C: Emergency ON before item2 — item3 not attempted", async () => {
    // phase 0: before item1 done; 1: allow item1 post-check; 2+: ON for item2+
    let phase = 0;
    const readEmergency = vi.fn(async () => {
      if (phase >= 2) {
        return { emergencyStopped: true, version: 19 };
      }
      if (phase === 1) {
        phase = 2;
        return { emergencyStopped: false, version: 18 };
      }
      return { emergencyStopped: false, version: 18 };
    });
    const analyze = vi.fn(async () => {
      phase = 1;
      return {
        status: "validated",
        providerCalls: 1,
        retries: 0,
        cacheHit: false,
        publishDelta: 0,
      };
    });
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"],
      deps: baseDeps({ readEmergency, analyze }),
    });
    expect(result.aborted).toBe(true);
    expect(result.abortCode).toBe("emergencyStopped");
    expect(result.succeeded).toBe(1);
    expect(analyze).toHaveBeenCalledTimes(1);
    expect(result.items[1]?.status).toBe("aborted_before_start");
    expect(result.items[2]?.status).toBe("aborted_before_start");
  });

  it("D: analyzed → no paid call", async () => {
    const analyze = vi.fn();
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({
        analyze,
        loadVideo: async () =>
          videoRow("vidAAAAAAA1", "ノエル", { analysisStatus: "analyzed" }),
      }),
    });
    expect(result.skipped).toBe(1);
    expect(result.attempted).toBe(0);
    expect(analyze).not.toHaveBeenCalled();
    expect(result.items[0]?.skipReason).toBe("alreadyAnalyzed");
  });

  it("E: covered → no paid call", async () => {
    const analyze = vi.fn();
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({
        analyze,
        loadCoveredCharacterIds: async () => new Set(["char_a"]),
      }),
    });
    expect(result.skipped).toBe(1);
    expect(analyze).not.toHaveBeenCalled();
    expect(result.items[0]?.skipReason).toBe("characterAlreadyCovered");
  });

  it("F: duplicate inflight → no paid call", async () => {
    const analyze = vi.fn();
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({
        analyze,
        countRunningJobs: async () => 1,
      }),
    });
    expect(result.skipped).toBe(1);
    expect(analyze).not.toHaveBeenCalled();
    expect(result.items[0]?.skipReason).toBe("analysisAlreadyRunning");
  });

  it("G: long-form item passes allowLongform:true into analyze", async () => {
    const analyze = vi.fn(async (input) => {
      expect(input.allowLongform).toBe(true);
      expect(input.force).toBe(false);
      expect(input.skipAutoPublish).toBe(true);
      return {
        status: "validated",
        providerCalls: 3,
        retries: 0,
        cacheHit: false,
        publishDelta: 0,
      };
    });
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({
        analyze,
        loadVideo: async () =>
          videoRow("vidAAAAAAA1", "ノエル", { durationSeconds: 1100 }),
      }),
    });
    expect(result.succeeded).toBe(1);
    expect(result.items[0]?.longform).toBe(true);
    expect(analyze).toHaveBeenCalledTimes(1);
  });

  it("H: publish env ON still publishCount=0; unexpected publish aborts", async () => {
    const analyze = vi.fn(async () => ({
      status: "validated",
      providerCalls: 1,
      retries: 0,
      cacheHit: false,
      // Harness must still treat any publishDelta as failure.
      publishDelta: 0,
      autoPublish: null,
    }));
    const ok = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({ analyze }),
    });
    expect(ok.publishCount).toBe(0);
    expect(ok.skipAutoPublish).toBe(true);

    const leaking = vi.fn(async () => ({
      status: "validated",
      providerCalls: 1,
      retries: 0,
      cacheHit: false,
      publishDelta: 2,
    }));
    const bad = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2"],
      deps: baseDeps({ analyze: leaking }),
    });
    expect(bad.aborted).toBe(true);
    expect(bad.abortCode).toBe("unexpectedPublish");
    expect(leaking).toHaveBeenCalledTimes(1);
    expect(bad.items[1]?.status).toBe("aborted_before_start");
  });

  it("I: maxItems > 3 rejects", async () => {
    await expect(
      runLimitedBatchCanary({
        videoIds: ["a", "b"],
        maxItems: 4,
        deps: baseDeps(),
      }),
    ).rejects.toMatchObject({ code: "maxItemsExceeded" } satisfies Partial<LimitedBatchCanaryError>);
  });

  it("J: only explicit videoIds are processed (no scan)", async () => {
    const loadVideo = vi.fn(async (id: string) => {
      if (id === "vidAAAAAAA1") return videoRow("vidAAAAAAA1", "ノエル");
      return null;
    });
    const analyze = vi.fn(async () => ({
      status: "validated",
      providerCalls: 1,
      retries: 0,
      cacheHit: false,
      publishDelta: 0,
    }));
    const result = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1"],
      deps: baseDeps({ loadVideo, analyze }),
    });
    expect(result.requested).toEqual(["vidAAAAAAA1"]);
    expect(loadVideo.mock.calls.map((c) => c[0])).toEqual(["vidAAAAAAA1"]);
    expect(result.attempted).toBe(1);
  });

  it("K: partial non-abort failure continues; safety failure aborts", async () => {
    const analyze = vi.fn(async (input: { videoId: string }) => {
      if (input.videoId === "vidAAAAAAA1") {
        throw new GuideVisualAnalysisError("invalidJson");
      }
      return {
        status: "validated",
        providerCalls: 1,
        retries: 0,
        cacheHit: false,
        publishDelta: 0,
      };
    });
    const continued = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2"],
      deps: baseDeps({ analyze }),
    });
    expect(continued.aborted).toBe(false);
    expect(continued.failed).toBe(1);
    expect(continued.succeeded).toBe(1);
    expect(analyze).toHaveBeenCalledTimes(2);

    const storm = vi.fn(async () => {
      throw new GuideVisualAnalysisError("http429");
    });
    const aborted = await runLimitedBatchCanary({
      videoIds: ["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"],
      deps: baseDeps({ analyze: storm }),
    });
    expect(aborted.aborted).toBe(true);
    expect(aborted.abortCode).toBe("http429");
    expect(storm).toHaveBeenCalledTimes(1);
  });

  it("rejects tooManyVideoIds without calling analyze", async () => {
    const analyze = vi.fn();
    await expect(
      runLimitedBatchCanary({
        videoIds: ["a", "b", "c", "d"],
        deps: baseDeps({ analyze }),
      }),
    ).rejects.toMatchObject({ code: "tooManyVideoIds" });
    expect(analyze).not.toHaveBeenCalled();
  });
});
