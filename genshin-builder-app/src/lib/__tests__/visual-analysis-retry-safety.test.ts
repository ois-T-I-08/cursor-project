import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  assertVisualProviderNotCoolingDown,
  assertVisualTokenBudget,
  classifyVisualAnalysisFailure,
  clearVisualProviderCooldownForTest,
  estimateVisualPromptTokens,
  geminiHttpRetryDelayMs,
  getVisualProviderCooldownRemainingMs,
  noteVisualProviderCooldown,
  parseRetryAfterMs,
  shouldAbortPendingBatch,
  VISUAL_PROMPT_TOKEN_HARD_MAX,
} from "../build-guides/visual-analysis-safety";
import { GeminiYouTubeVisualAnalysisProvider } from "../build-guides/gemini-youtube-provider";

describe("visual-analysis-safety policy", () => {
  afterEach(() => {
    clearVisualProviderCooldownForTest();
  });

  it("classifies analysisFailed as non-retryable", () => {
    expect(classifyVisualAnalysisFailure("analysisFailed")).toEqual({
      retryable: false,
      abortBatch: false,
      providerCooldown: false,
    });
  });

  it("classifies http429 as retryable with batch abort + provider cooldown", () => {
    expect(classifyVisualAnalysisFailure("http429")).toEqual({
      retryable: true,
      abortBatch: true,
      providerCooldown: true,
    });
    expect(shouldAbortPendingBatch("http429")).toBe(true);
    expect(shouldAbortPendingBatch("providerRateLimited")).toBe(true);
    expect(shouldAbortPendingBatch("emergencyStopped")).toBe(true);
  });

  it("parses Retry-After seconds and HTTP-date", () => {
    expect(parseRetryAfterMs("12")).toBe(12_000);
    const now = Date.UTC(2026, 7, 8, 0, 0, 0);
    const header = new Date(now + 45_000).toUTCString();
    expect(parseRetryAfterMs(header, now)).toBe(45_000);
  });

  it("429 without Retry-After uses exponential backoff + jitter (not immediate)", () => {
    const d1 = geminiHttpRetryDelayMs({
      attempt: 1,
      status: 429,
      random: () => 0,
    });
    const d2 = geminiHttpRetryDelayMs({
      attempt: 2,
      status: 429,
      random: () => 0,
    });
    expect(d1).toBeGreaterThanOrEqual(5_000);
    expect(d2).toBeGreaterThanOrEqual(d1);
    expect(d1).toBe(5_000);
    expect(d2).toBe(10_000);
  });

  it("429 with Retry-After respects header before retry", () => {
    const delay = geminiHttpRetryDelayMs({
      attempt: 1,
      status: 429,
      retryAfterHeader: "90",
      random: () => 0,
    });
    expect(delay).toBe(90_000);
  });

  it("provider cooldown blocks concurrent storm across jobs", () => {
    noteVisualProviderCooldown(30_000);
    expect(getVisualProviderCooldownRemainingMs()).toBeGreaterThan(0);
    expect(() => assertVisualProviderNotCoolingDown()).toThrow(
      /geminiProviderCoolingDown/,
    );
  });

  it("token guard estimates duration-based media tokens and enforces hard max", () => {
    const estimated = estimateVisualPromptTokens({
      durationSeconds: 1_198,
      fps: 1,
      analysisMode: "full_discovery",
      targetCharacterCount: 1,
    });
    expect(estimated).toBeGreaterThan(VISUAL_PROMPT_TOKEN_HARD_MAX);
    expect(() =>
      assertVisualTokenBudget({
        durationSeconds: 1_198,
        fps: 1,
        analysisMode: "full_discovery",
        targetCharacterCount: 1,
      }),
    ).toThrow(/videoTooLargeForFullDiscovery/);

    const clippedOk = assertVisualTokenBudget({
      durationSeconds: 1_198,
      fps: 3,
      analysisMode: "clipped_detail",
      rangeSecondsTotal: 60,
      targetCharacterCount: 1,
    });
    expect(clippedOk.estimatedTokens).toBeLessThan(VISUAL_PROMPT_TOKEN_HARD_MAX);
  });
});

describe("Gemini visual 429 / emergency retry behavior", () => {
  const env = { ...process.env };

  beforeEach(() => {
    process.env.GEMINI_VIDEO_ANALYSIS_ENABLED = "true";
    process.env.GEMINI_API_KEY = "test-gemini-key";
    process.env.GEMINI_VIDEO_ANALYSIS_MODEL = "gemini-3.6-flash";
    process.env.GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS = "3";
    process.env.GEMINI_VIDEO_DISCOVERY_FPS = "1";
    process.env.GEMINI_VIDEO_DETAIL_FPS = "3";
    process.env.GEMINI_VIDEO_MAX_DETAIL_FPS = "5";
    clearVisualProviderCooldownForTest();
  });

  afterEach(() => {
    process.env = { ...env };
    clearVisualProviderCooldownForTest();
  });

  function okBody() {
    return {
      candidates: [
        {
          content: {
            parts: [
              {
                text: JSON.stringify({
                  videoId: "abcdefghijk",
                  relevant: true,
                  detectedCharacterIds: [],
                  evidences: [],
                  unresolvedEntities: [],
                  analysisSummary: "ok",
                }),
              },
            ],
          },
        },
      ],
    };
  }

  it("429 does not immediate-retry; sleeps Retry-After then retries", async () => {
    const sleeps: number[] = [];
    let calls = 0;
    const fetchImpl = vi.fn(async () => {
      calls += 1;
      if (calls === 1) {
        return new Response("rate limited", {
          status: 429,
          headers: { "retry-after": "2" },
        });
      }
      return Response.json(okBody());
    });

    const provider = new GeminiYouTubeVisualAnalysisProvider({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      random: () => 0,
    });

    await provider.analyze({
      videoId: "abcdefghijk",
      youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
      channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
      title: "guide",
      publishedAt: null,
      durationSeconds: 120,
      targetCharacterIds: ["hu-tao"],
      analysisMode: "full_discovery",
      fps: 1,
      gameDataVersion: "v1",
    });

    expect(calls).toBe(2);
    expect(sleeps).toHaveLength(1);
    expect(sleeps[0]).toBeGreaterThanOrEqual(2_000);
    expect(getVisualProviderCooldownRemainingMs()).toBeGreaterThan(0);
  });

  it("429 without Retry-After uses exponential backoff (not tight loop)", async () => {
    const sleeps: number[] = [];
    process.env.GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS = "3";
    const fetchImpl = vi.fn(
      async () =>
        new Response("rate limited", {
          status: 429,
        }),
    );

    const provider = new GeminiYouTubeVisualAnalysisProvider({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      random: () => 0,
    });

    await expect(
      provider.analyze({
        videoId: "abcdefghijk",
        youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
        channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
        title: "guide",
        publishedAt: null,
        durationSeconds: 120,
        targetCharacterIds: [],
        analysisMode: "full_discovery",
        fps: 1,
        gameDataVersion: "v1",
      }),
    ).rejects.toMatchObject({ code: "http429" });

    expect(fetchImpl).toHaveBeenCalledTimes(3);
    expect(sleeps).toEqual([5_000, 10_000]);
  });

  it("max attempts exceeded becomes terminal failure", async () => {
    process.env.GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS = "2";
    const fetchImpl = vi.fn(
      async () => new Response("boom", { status: 503 }),
    );
    const sleeps: number[] = [];
    const provider = new GeminiYouTubeVisualAnalysisProvider({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      random: () => 0,
    });
    await expect(
      provider.analyze({
        videoId: "abcdefghijk",
        youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
        channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
        title: "guide",
        publishedAt: null,
        durationSeconds: 120,
        targetCharacterIds: [],
        analysisMode: "full_discovery",
        fps: 1,
        gameDataVersion: "v1",
      }),
    ).rejects.toMatchObject({ code: "http503", retryable: true });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleeps).toHaveLength(1);
  });

  it("two jobs hitting 429 engage provider cooldown (no storm)", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response("rate limited", {
          status: 429,
          headers: { "retry-after": "60" },
        }),
    );
    process.env.GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS = "1";
    const provider = new GeminiYouTubeVisualAnalysisProvider({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
      random: () => 0,
    });
    await expect(
      provider.analyze({
        videoId: "abcdefghijk",
        youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
        channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
        title: "a",
        publishedAt: null,
        durationSeconds: 60,
        targetCharacterIds: [],
        analysisMode: "full_discovery",
        fps: 1,
        gameDataVersion: "v1",
      }),
    ).rejects.toMatchObject({ code: "http429" });
    expect(() => assertVisualProviderNotCoolingDown()).toThrow();
    // Second job must not call provider while cooling down (gate is in service).
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});

describe("Global AI Emergency gate on visual provider", () => {
  const env = { ...process.env };

  beforeEach(() => {
    process.env.GEMINI_VIDEO_ANALYSIS_ENABLED = "true";
    process.env.GEMINI_API_KEY = "test-gemini-key";
    process.env.GEMINI_VIDEO_ANALYSIS_MODEL = "gemini-3.6-flash";
    vi.resetModules();
  });

  afterEach(() => {
    process.env = { ...env };
    vi.doUnmock("@/lib/ai/global-ai-emergency");
    vi.resetModules();
  });

  it("pending retry makes 0 API calls when emergency is ON", async () => {
    vi.doMock("@/lib/ai/global-ai-emergency", () => ({
      assertGlobalAiEmergencyAllowsExternalCall: vi.fn(async () => {
        throw new Error("EMERGENCY_STOPPED");
      }),
    }));
    const { GeminiYouTubeVisualAnalysisProvider: Provider } = await import(
      "../build-guides/gemini-youtube-provider"
    );
    const fetchImpl = vi.fn(async () => Response.json({}));
    const provider = new Provider({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
      random: () => 0,
    });
    await expect(
      provider.analyze({
        videoId: "abcdefghijk",
        youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
        channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
        title: "guide",
        publishedAt: null,
        durationSeconds: 120,
        targetCharacterIds: [],
        analysisMode: "full_discovery",
        fps: 1,
        gameDataVersion: "v1",
      }),
    ).rejects.toMatchObject({ code: "EMERGENCY_STOPPED", retryable: false });
    expect(fetchImpl).toHaveBeenCalledTimes(0);
  });
});
