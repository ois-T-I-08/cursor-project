import "server-only";

import { createHash } from "node:crypto";
import { z } from "zod";

const YOUTUBE_API_BASE = "https://www.googleapis.com/youtube/v3/";
const MAX_RESPONSE_BYTES = 2_097_152;

const channelListSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.string().min(1),
        snippet: z.object({
          title: z.string(),
          description: z.string().optional().default(""),
          customUrl: z.string().optional().default(""),
          thumbnails: z
            .object({
              default: z.object({ url: z.string() }).optional(),
              medium: z.object({ url: z.string() }).optional(),
              high: z.object({ url: z.string() }).optional(),
            })
            .optional(),
        }),
        contentDetails: z
          .object({
            relatedPlaylists: z.object({ uploads: z.string() }).optional(),
          })
          .optional(),
      }),
    )
    .default([]),
});

const playlistItemsSchema = z.object({
  nextPageToken: z.string().optional(),
  items: z
    .array(
      z.object({
        contentDetails: z.object({ videoId: z.string().min(1) }),
        snippet: z
          .object({
            title: z.string().optional(),
            description: z.string().optional(),
            publishedAt: z.string().optional(),
            thumbnails: z
              .object({
                default: z.object({ url: z.string() }).optional(),
                medium: z.object({ url: z.string() }).optional(),
                high: z.object({ url: z.string() }).optional(),
              })
              .optional(),
          })
          .optional(),
      }),
    )
    .default([]),
});

const videosListSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.string().min(1),
        snippet: z.object({
          title: z.string(),
          description: z.string().optional().default(""),
          publishedAt: z.string().optional(),
          channelId: z.string(),
          thumbnails: z
            .object({
              default: z.object({ url: z.string() }).optional(),
              medium: z.object({ url: z.string() }).optional(),
              high: z.object({ url: z.string() }).optional(),
            })
            .optional(),
        }),
        contentDetails: z
          .object({
            duration: z.string().optional(),
          })
          .optional(),
        status: z
          .object({
            privacyStatus: z.string().optional(),
          })
          .optional(),
      }),
    )
    .default([]),
});

export class YoutubeError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "YoutubeError";
  }
}

export interface YoutubeChannelInfo {
  channelId: string;
  title: string;
  description: string;
  customUrl: string;
  thumbnailUrl: string;
  uploadsPlaylistId: string;
}

export interface YoutubeVideoInfo {
  videoId: string;
  channelId: string;
  title: string;
  description: string;
  publishedAt: Date | null;
  thumbnailUrl: string;
  sourceUrl: string;
  metadataHash: string;
  durationSeconds: number | null;
  privacyStatus: string;
}

export interface YoutubeClientOptions {
  fetchImpl?: typeof fetch;
  apiKey?: string;
}

export class YoutubeGuideClient {
  private readonly fetchImpl: typeof fetch;
  private readonly apiKey: string | undefined;

  constructor(options: YoutubeClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.apiKey = options.apiKey ?? process.env.YOUTUBE_API_KEY?.trim();
  }

  assertEnabled(): void {
    if (process.env.YOUTUBE_GUIDE_ENABLED !== "true") {
      throw new YoutubeError("youtubeDisabled");
    }
    if (!this.apiKey) throw new YoutubeError("youtubeNotConfigured");
  }

  async fetchChannel(channelId: string): Promise<YoutubeChannelInfo> {
    this.assertEnabled();
    const data = await this.getJson("channels", {
      part: "snippet,contentDetails",
      id: channelId,
      maxResults: "1",
    });
    const parsed = channelListSchema.parse(data);
    const item = parsed.items[0];
    if (!item) throw new YoutubeError("channelNotFound");
    const uploads = item.contentDetails?.relatedPlaylists?.uploads;
    if (!uploads) throw new YoutubeError("uploadsPlaylistMissing");
    const thumbs = item.snippet.thumbnails;
    return {
      channelId: item.id,
      title: item.snippet.title,
      description: item.snippet.description ?? "",
      customUrl: item.snippet.customUrl ?? "",
      thumbnailUrl: thumbs?.high?.url ?? thumbs?.medium?.url ?? thumbs?.default?.url ?? "",
      uploadsPlaylistId: uploads,
    };
  }

  async listUploadVideoIds(
    uploadsPlaylistId: string,
    options: { maxPages?: number } = {},
  ): Promise<string[]> {
    this.assertEnabled();
    const maxPages = options.maxPages ?? 5;
    const ids: string[] = [];
    let pageToken: string | undefined;
    for (let page = 0; page < maxPages; page++) {
      const data = await this.getJson("playlistItems", {
        part: "contentDetails,snippet",
        playlistId: uploadsPlaylistId,
        maxResults: "50",
        ...(pageToken ? { pageToken } : {}),
      });
      const parsed = playlistItemsSchema.parse(data);
      for (const item of parsed.items) {
        ids.push(item.contentDetails.videoId);
      }
      pageToken = parsed.nextPageToken;
      if (!pageToken) break;
    }
    return [...new Set(ids)];
  }

  async fetchVideos(videoIds: string[]): Promise<YoutubeVideoInfo[]> {
    this.assertEnabled();
    const unique = [...new Set(videoIds)].filter(Boolean);
    const out: YoutubeVideoInfo[] = [];
    for (let i = 0; i < unique.length; i += 50) {
      const batch = unique.slice(i, i + 50);
      if (batch.length === 0) continue;
      const data = await this.getJson("videos", {
        part: "snippet,contentDetails,status",
        id: batch.join(","),
        maxResults: "50",
      });
      const parsed = videosListSchema.parse(data);
      for (const item of parsed.items) {
        const thumbs = item.snippet.thumbnails;
        const thumbnailUrl =
          thumbs?.high?.url ?? thumbs?.medium?.url ?? thumbs?.default?.url ?? "";
        const publishedAt = item.snippet.publishedAt
          ? new Date(item.snippet.publishedAt)
          : null;
        const sourceUrl = `https://www.youtube.com/watch?v=${item.id}`;
        const durationSeconds = parseIso8601Duration(
          item.contentDetails?.duration ?? "",
        );
        const privacyStatus = item.status?.privacyStatus ?? "unknown";
        const metadataHash = createHash("sha256")
          .update(
            JSON.stringify({
              title: item.snippet.title,
              description: item.snippet.description ?? "",
              publishedAt: item.snippet.publishedAt ?? "",
              thumbnailUrl,
              durationSeconds,
              privacyStatus,
            }),
            "utf8",
          )
          .digest("hex");
        out.push({
          videoId: item.id,
          channelId: item.snippet.channelId,
          title: item.snippet.title,
          description: item.snippet.description ?? "",
          publishedAt:
            publishedAt && !Number.isNaN(publishedAt.getTime()) ? publishedAt : null,
          thumbnailUrl,
          sourceUrl,
          metadataHash,
          durationSeconds,
          privacyStatus,
        });
      }
    }
    return out;
  }

  private async getJson(
    resource: "channels" | "playlistItems" | "videos",
    params: Record<string, string>,
  ): Promise<unknown> {
    if (!this.apiKey) throw new YoutubeError("youtubeNotConfigured");
    const url = new URL(resource, YOUTUBE_API_BASE);
    if (url.origin !== "https://www.googleapis.com" || !url.pathname.startsWith("/youtube/v3/")) {
      throw new YoutubeError("invalidYoutubeHost");
    }
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
    url.searchParams.set("key", this.apiKey);

    const controller = new AbortController();
    const timeoutMs = clampTimeout(process.env.YOUTUBE_TIMEOUT_MS, 15_000);
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await this.fetchImpl(url.toString(), {
        method: "GET",
        headers: {
          Accept: "application/json",
          "User-Agent": "genshin-builder/1.0 (build-guides-youtube)",
        },
        signal: controller.signal,
        cache: "no-store",
      });
      if (!response.ok) {
        if (response.status === 403 || response.status === 401) {
          throw new YoutubeError("youtubeAuthFailed");
        }
        if (response.status === 404) throw new YoutubeError("youtubeNotFound");
        if ([429, 500, 503].includes(response.status)) {
          throw new YoutubeError(`youtubeHttp${response.status}`);
        }
        throw new YoutubeError("youtubeRequestFailed");
      }
      const raw = await response.text();
      if (Buffer.byteLength(raw, "utf8") > MAX_RESPONSE_BYTES) {
        throw new YoutubeError("youtubeResponseTooLarge");
      }
      return JSON.parse(raw) as unknown;
    } catch (error) {
      if (error instanceof YoutubeError) throw error;
      if (error instanceof DOMException && error.name === "AbortError") {
        throw new YoutubeError("youtubeTimeout");
      }
      if (error instanceof SyntaxError) throw new YoutubeError("youtubeInvalidJson");
      throw new YoutubeError("youtubeNetworkError");
    } finally {
      clearTimeout(timeout);
    }
  }
}

function clampTimeout(raw: string | undefined, fallback: number): number {
  const value = Number(raw);
  return Number.isFinite(value) ? Math.min(60_000, Math.max(3_000, Math.round(value))) : fallback;
}

/** Parse YouTube contentDetails.duration (ISO-8601) e.g. PT1H2M3S */
export function parseIso8601Duration(value: string): number | null {
  const match = value.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) return null;
  const hours = Number(match[1] ?? 0);
  const minutes = Number(match[2] ?? 0);
  const seconds = Number(match[3] ?? 0);
  const total = hours * 3600 + minutes * 60 + seconds;
  return Number.isFinite(total) ? total : null;
}
