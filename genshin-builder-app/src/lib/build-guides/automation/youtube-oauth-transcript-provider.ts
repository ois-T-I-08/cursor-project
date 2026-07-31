import "server-only";

import { z } from "zod";
import {
  classifyProviderHttpStatus,
  SafeProviderError,
  toSafeProviderError,
} from "./provider-error";
import { parseWebVtt } from "./transcript-normalize";
import type {
  TranscriptDocument,
  TranscriptProvider,
  TranscriptTrack,
} from "./transcript-provider";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";

const YOUTUBE_API_ORIGIN = "https://www.googleapis.com";
const PROVIDER_ID = "youtube-oauth-captions-v1";

const captionListSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.string().min(1),
        snippet: z.object({
          language: z.string().min(1),
          trackKind: z.string().optional().default("standard"),
          isDraft: z.boolean().optional().default(false),
        }),
      }),
    )
    .default([]),
});

export class YouTubeOAuthTranscriptProvider implements TranscriptProvider {
  readonly providerId = PROVIDER_ID;
  private readonly fetchImpl: typeof fetch;
  private readonly accessToken: string | undefined;
  private readonly timeoutMs: number;

  constructor(
    options: {
      fetchImpl?: typeof fetch;
      accessToken?: string;
      timeoutMs?: number;
    } = {},
  ) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.accessToken =
      options.accessToken?.trim() ||
      process.env.YOUTUBE_OAUTH_ACCESS_TOKEN?.trim() ||
      undefined;
    this.timeoutMs = Math.min(60_000, Math.max(3_000, options.timeoutMs ?? 15_000));
  }

  async listTracks(videoId: string): Promise<readonly TranscriptTrack[]> {
    const url = this.safeUrl("/youtube/v3/captions");
    url.searchParams.set("part", "snippet");
    url.searchParams.set("videoId", assertVideoId(videoId));
    const raw = await this.request(url, "application/json");
    let decoded: unknown;
    try {
      decoded = JSON.parse(raw) as unknown;
    } catch {
      throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
    }
    const parsed = captionListSchema.safeParse(decoded);
    if (!parsed.success) {
      throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
    }
    return parsed.data.items.map((item) => ({
      trackId: item.id,
      language: item.snippet.language,
      trackKind: item.snippet.trackKind === "ASR" ? "asr" : "manual",
      isDraft: item.snippet.isDraft,
    }));
  }

  async fetchTrack(
    videoId: string,
    track: TranscriptTrack,
  ): Promise<TranscriptDocument> {
    assertVideoId(videoId);
    const url = this.safeUrl(
      `/youtube/v3/captions/${encodeURIComponent(assertTrackId(track.trackId))}`,
    );
    url.searchParams.set("tfmt", "vtt");
    const raw = await this.request(url, "text/vtt");
    return {
      providerId: this.providerId,
      videoId,
      language: track.language,
      trackKind: track.trackKind,
      sourceTrackId: track.trackId,
      segments: parseWebVtt(raw),
      fetchedAt: new Date(),
    };
  }

  private safeUrl(pathname: string): URL {
    const url = new URL(pathname, YOUTUBE_API_ORIGIN);
    if (
      url.origin !== YOUTUBE_API_ORIGIN ||
      !url.pathname.startsWith("/youtube/v3/captions")
    ) {
      throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
    }
    return url;
  }

  private async request(url: URL, accept: string): Promise<string> {
    if (!this.accessToken) {
      throw new SafeProviderError(
        this.providerId,
        "AUTH_NOT_CONFIGURED",
        false,
      );
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(url.toString(), {
        method: "GET",
        headers: {
          Accept: accept,
          Authorization: `Bearer ${this.accessToken}`,
          "User-Agent": "genshin-builder/1.0 (youtube-oauth-captions)",
        },
        signal: controller.signal,
        cache: "no-store",
      });
      if (!response.ok) {
        throw classifyProviderHttpStatus(this.providerId, response.status);
      }
      const length = Number(response.headers.get("content-length") ?? 0);
      if (
        Number.isFinite(length) &&
        length > YOUTUBE_AUTOMATION_POLICY.maxTranscriptBytes
      ) {
        throw new SafeProviderError(
          this.providerId,
          "RESPONSE_TOO_LARGE",
          false,
        );
      }
      const raw = await response.text();
      if (
        Buffer.byteLength(raw, "utf8") >
        YOUTUBE_AUTOMATION_POLICY.maxTranscriptBytes
      ) {
        throw new SafeProviderError(
          this.providerId,
          "RESPONSE_TOO_LARGE",
          false,
        );
      }
      return raw;
    } catch (error) {
      throw toSafeProviderError(this.providerId, error);
    } finally {
      clearTimeout(timeout);
    }
  }
}

function assertVideoId(videoId: string): string {
  if (!/^[A-Za-z0-9_-]{6,20}$/.test(videoId)) {
    throw new SafeProviderError(PROVIDER_ID, "INVALID_RESPONSE", false);
  }
  return videoId;
}

function assertTrackId(trackId: string): string {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(trackId)) {
    throw new SafeProviderError(PROVIDER_ID, "INVALID_RESPONSE", false);
  }
  return trackId;
}
