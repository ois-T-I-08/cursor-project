import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildVisualRequestHash } from "../build-guides/cache-key";
import {
  GEMINI_ALLOWED_VIDEO_MODELS,
  GeminiError,
} from "../build-guides/gemini-settings";
import {
  buildVideoPart,
  GeminiYouTubeVisualAnalysisProvider,
} from "../build-guides/gemini-youtube-provider";

describe("GeminiYouTubeVisualAnalysisProvider", () => {
  const env = { ...process.env };

  beforeEach(() => {
    process.env.GEMINI_VIDEO_ANALYSIS_ENABLED = "true";
    process.env.GEMINI_API_KEY = "test-gemini-key";
    process.env.GEMINI_VIDEO_ANALYSIS_MODEL = "gemini-3.6-flash";
    process.env.GEMINI_VIDEO_DISCOVERY_FPS = "1";
    process.env.GEMINI_VIDEO_DETAIL_FPS = "3";
    process.env.GEMINI_VIDEO_MAX_DETAIL_FPS = "5";
  });

  afterEach(() => {
    process.env = { ...env };
  });

  it("allows primary 3.6 and temporary 2.5 fallbacks, rejects retired 2.0", () => {
    expect(GEMINI_ALLOWED_VIDEO_MODELS.has("gemini-3.6-flash")).toBe(true);
    expect(GEMINI_ALLOWED_VIDEO_MODELS.has("gemini-2.5-flash")).toBe(true);
    expect(GEMINI_ALLOWED_VIDEO_MODELS.has("gemini-2.5-pro")).toBe(true);
    expect(GEMINI_ALLOWED_VIDEO_MODELS.has("gemini-2.0-flash")).toBe(false);
  });

  it("fails closed when disabled or unsupported model", async () => {
    process.env.GEMINI_VIDEO_ANALYSIS_ENABLED = "false";
    const provider = new GeminiYouTubeVisualAnalysisProvider();
    await expect(
      provider.analyze({
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
      }),
    ).rejects.toBeInstanceOf(GeminiError);

    process.env.GEMINI_VIDEO_ANALYSIS_ENABLED = "true";
    process.env.GEMINI_VIDEO_ANALYSIS_MODEL = "gemini-2.0-flash";
    await expect(
      provider.analyze({
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
      }),
    ).rejects.toMatchObject({ code: "unsupportedGeminiModel" });
  });

  it("does not send deprecated sampling parameters for 3.6 Flash", async () => {
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as {
        generationConfig: Record<string, unknown>;
      };
      expect(body.generationConfig).toEqual({
        responseMimeType: "application/json",
      });
      expect(body.generationConfig).not.toHaveProperty("temperature");
      expect(body.generationConfig).not.toHaveProperty("top_p");
      expect(body.generationConfig).not.toHaveProperty("topP");
      expect(body.generationConfig).not.toHaveProperty("top_k");
      expect(body.generationConfig).not.toHaveProperty("topK");
      expect(body.generationConfig).not.toHaveProperty("candidate_count");
      expect(body.generationConfig).not.toHaveProperty("candidateCount");
      expect(body.generationConfig).not.toHaveProperty("thinking_budget");
      expect(body.generationConfig).not.toHaveProperty("thinkingBudget");
      const serialized = JSON.stringify(body);
      expect(serialized).not.toMatch(/temperature|top_p|top_k|candidate_count|thinking_budget/i);
      return Response.json({
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
      });
    });

    const provider = new GeminiYouTubeVisualAnalysisProvider({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
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
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("clips selected ranges via video_metadata and does not send full-video-only parts", async () => {
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as {
        contents: Array<{
          parts: Array<{
            file_data?: { file_uri: string; mime_type?: string };
            video_metadata?: {
              start_offset?: string;
              end_offset?: string;
              fps?: number;
            };
            text?: string;
          }>;
        }>;
      };
      const videoPart = body.contents[0]?.parts.find((p) => p.file_data);
      expect(videoPart?.file_data?.file_uri).toBe(
        "https://www.youtube.com/watch?v=abcdefghijk",
      );
      expect(videoPart?.video_metadata).toEqual({
        fps: 3,
        start_offset: "120s",
        end_offset: "150s",
      });
      expect(videoPart?.video_metadata).toHaveProperty("start_offset");
      expect(videoPart?.video_metadata).toHaveProperty("end_offset");
      return Response.json({
        candidates: [
          {
            content: {
              parts: [
                {
                  text: JSON.stringify({
                    videoId: "abcdefghijk",
                    relevant: true,
                    detectedCharacterIds: ["hu-tao"],
                    evidences: [],
                    unresolvedEntities: [],
                    analysisSummary: "clipped",
                  }),
                },
              ],
            },
          },
        ],
        usageMetadata: { totalTokenCount: 5 },
      });
    });

    const provider = new GeminiYouTubeVisualAnalysisProvider({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
      random: () => 0,
    });
    await provider.analyze({
      videoId: "abcdefghijk",
      youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
      channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
      title: "guide",
      publishedAt: null,
      durationSeconds: 600,
      targetCharacterIds: ["hu-tao"],
      analysisMode: "clipped_detail",
      fps: 3,
      requestedRanges: [
        { startSeconds: 120, endSeconds: 150, reason: "stat-table" },
      ],
      gameDataVersion: "v1",
    });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("issues one Gemini request per clipped range", async () => {
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as {
        contents: Array<{
          parts: Array<{
            video_metadata?: { start_offset?: string; end_offset?: string };
          }>;
        }>;
      };
      const meta = body.contents[0]?.parts.find((p) => p.video_metadata)?.video_metadata;
      expect(meta?.start_offset).toBeDefined();
      expect(meta?.end_offset).toBeDefined();
      return Response.json({
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
                    analysisSummary: "range",
                  }),
                },
              ],
            },
          },
        ],
      });
    });

    const provider = new GeminiYouTubeVisualAnalysisProvider({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      sleep: async () => undefined,
      random: () => 0,
    });
    await provider.analyze({
      videoId: "abcdefghijk",
      youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
      channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
      title: "guide",
      publishedAt: null,
      durationSeconds: 600,
      targetCharacterIds: [],
      analysisMode: "clipped_detail",
      fps: 3,
      requestedRanges: [
        { startSeconds: 10, endSeconds: 20, reason: "a" },
        { startSeconds: 40, endSeconds: 55, reason: "b" },
      ],
      gameDataVersion: "v1",
    });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it("buildVideoPart separates full discovery from clipped detail", () => {
    const full = buildVideoPart({
      youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
      fps: 1,
      clip: null,
    });
    expect(full.file_data).toEqual({
      file_uri: "https://www.youtube.com/watch?v=abcdefghijk",
      mime_type: "video/*",
    });
    expect(full).not.toHaveProperty("video_metadata");

    const clipped = buildVideoPart({
      youtubeUrl: "https://www.youtube.com/watch?v=abcdefghijk",
      fps: 3,
      clip: { startSeconds: 90, endSeconds: 120, reason: "detail" },
    });
    expect(clipped.video_metadata).toEqual({
      fps: 3,
      start_offset: "90s",
      end_offset: "120s",
    });
  });

  it("separates cache keys for full vs clipped analysis and FPS", () => {
    const base = {
      videoId: "abcdefghijk",
      videoMetadataHash: "meta",
      videoPublishedAt: null,
      videoDuration: 600,
      providerId: "gemini",
      modelIdentifier: "gemini-3.6-flash",
      visualPromptVersion: "v1",
      visualSchemaVersion: "v1",
      gameDataVersion: "g1",
    };
    const full = buildVisualRequestHash({
      ...base,
      analysisMode: "full_discovery",
      fps: 1,
    });
    const clipped = buildVisualRequestHash({
      ...base,
      analysisMode: "clipped_detail",
      fps: 3,
      requestedRanges: [{ startSeconds: 100, endSeconds: 130 }],
    });
    const clippedOtherFps = buildVisualRequestHash({
      ...base,
      analysisMode: "clipped_detail",
      fps: 5,
      requestedRanges: [{ startSeconds: 100, endSeconds: 130 }],
    });
    expect(full).not.toBe(clipped);
    expect(clipped).not.toBe(clippedOtherFps);
  });

  it("rejects arbitrary youtube hosts", async () => {
    const provider = new GeminiYouTubeVisualAnalysisProvider();
    await expect(
      provider.analyze({
        videoId: "abcdefghijk",
        youtubeUrl: "https://evil.example/watch?v=abcdefghijk",
        channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
        title: "x",
        publishedAt: null,
        durationSeconds: 10,
        targetCharacterIds: [],
        analysisMode: "full_discovery",
        fps: 1,
        gameDataVersion: "v1",
      }),
    ).rejects.toMatchObject({ code: "invalidYoutubeHost" });
  });
});
