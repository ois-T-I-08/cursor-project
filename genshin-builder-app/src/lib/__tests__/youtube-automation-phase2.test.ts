import { describe, expect, it, vi } from "vitest";
import {
  transcriptAnalysisSchema,
  validateTranscriptAnalysis,
} from "@/lib/build-guides/automation/analysis-schema";
import {
  classifyProviderHttpStatus,
  SafeProviderError,
  toSafeProviderError,
} from "@/lib/build-guides/automation/provider-error";
import {
  chunkTranscript,
  normalizeTranscript,
  parseWebVtt,
} from "@/lib/build-guides/automation/transcript-normalize";
import {
  fetchPreferredTranscript,
  type TranscriptDocument,
} from "@/lib/build-guides/automation/transcript-provider";
import { DeterministicTranscriptProvider } from "@/lib/build-guides/automation/testing-transcript-provider";
import { YouTubeOAuthTranscriptProvider } from "@/lib/build-guides/automation/youtube-oauth-transcript-provider";
import { runWithFiniteRetry } from "@/lib/build-guides/automation/retry";
import { evaluateDiscoveryCandidate } from "@/lib/build-guides/automation/discovery-policy";
import { youtubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import type { YoutubeVideoInfo } from "@/lib/build-guides/youtube-client";
import { GeminiTranscriptAnalysisProvider } from "@/lib/build-guides/automation/gemini-transcript-provider";

const document: TranscriptDocument = {
  providerId: "fixture",
  videoId: "video_12345",
  language: "ja",
  trackKind: "manual",
  sourceTrackId: "track-1",
  fetchedAt: new Date("2026-07-31T00:00:00.000Z"),
  segments: [
    {
      startSeconds: 1,
      durationSeconds: 2,
      text: "雷電将軍には漁獲がおすすめです。",
    },
    {
      startSeconds: 3,
      durationSeconds: 2.5,
      text: "時計のメインステータスは元素チャージ効率です。",
    },
  ],
};

describe("YouTube automation Phase 2", () => {
  it("fails every automation flag closed unless explicitly enabled", () => {
    expect(youtubeAutomationFlags({})).toEqual({
      enabled: false,
      guideEnabled: false,
      discoveryEnabled: false,
      transcriptEnabled: false,
      analysisEnabled: false,
      geminiAnalysisEnabled: false,
      deepseekAnalysisEnabled: false,
      autoPublishEnabled: false,
      maintenanceEnabled: false,
    });
    expect(
      youtubeAutomationFlags({
        YOUTUBE_AUTOMATION_ENABLED: "true",
        YOUTUBE_GUIDE_ENABLED: "true",
      }),
    ).toMatchObject({
      enabled: true,
      guideEnabled: true,
      transcriptEnabled: true,
      analysisEnabled: false,
    });
  });

  it("selects a deterministic official transcript and blocks when absent", async () => {
    const provider = new DeterministicTranscriptProvider(
      new Map([[document.videoId, document]]),
    );
    const found = await fetchPreferredTranscript(provider, document.videoId);
    expect(found.ok).toBe(true);
    const missing = await fetchPreferredTranscript(provider, "missing_123");
    expect(missing).toMatchObject({
      ok: false,
      blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE",
      error: { safeCode: "TRANSCRIPT_UNAVAILABLE", retryable: false },
    });
  });

  it("does not call YouTube when OAuth credentials are absent", async () => {
    const fetchImpl = vi.fn();
    const provider = new YouTubeOAuthTranscriptProvider({
      accessToken: " ",
      fetchImpl,
    });
    const result = await fetchPreferredTranscript(provider, "video_12345");
    expect(result).toMatchObject({
      ok: false,
      blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE",
      error: { safeCode: "AUTH_NOT_CONFIGURED", retryable: false },
    });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("parses, normalizes, hashes, and chunks WebVTT deterministically", () => {
    const segments = parseWebVtt(
      "WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n雷電将軍には <b>漁獲</b> がおすすめです。\n\n00:03.000 --> 00:05.500\n時計は元素チャージ効率。\n",
    );
    const first = normalizeTranscript({ ...document, segments });
    const second = normalizeTranscript({ ...document, segments });
    expect(first.transcriptHash).toBe(second.transcriptHash);
    expect(first.segments[0]?.text).toBe("雷電将軍には 漁獲 がおすすめです。");
    expect(chunkTranscript(first, 100, 1)).toHaveLength(2);
  });

  it("accepts only known entities with exact transcript evidence and timestamps", () => {
    const transcript = normalizeTranscript(document);
    const segmentId = transcript.segments[0]!.segmentKey;
    const value = validAnalysis(segmentId);
    const result = validateTranscriptAnalysis(value, {
      expectedCharacterId: "raiden-shogun",
      knownEntityIds: new Set(["the-catch"]),
      transcript,
    });
    expect(result).toMatchObject({
      ok: true,
      claims: [{ startSeconds: 1, endSeconds: 3 }],
      quality: {
        citationCoverage: 1,
        timestampCoverage: 1,
        entityCoverage: 1,
      },
    });
  });

  it.each([
    [
      "schema",
      (value: ReturnType<typeof validAnalysis>) => ({ ...value, extra: true }),
      "BLOCKED_ANALYSIS_SCHEMA_INVALID",
    ],
    [
      "timestamp range",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        claims: [{ ...value.claims[0]!, timestampStart: -1 }],
      }),
      "BLOCKED_ANALYSIS_SCHEMA_INVALID",
    ],
    [
      "character",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        characterId: "unknown",
      }),
      "BLOCKED_CHARACTER_MISMATCH",
    ],
    [
      "entity",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        claims: [{ ...value.claims[0]!, entityId: "made-up-weapon" }],
      }),
      "BLOCKED_UNKNOWN_ENTITY",
    ],
    [
      "citation",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        claims: [{ ...value.claims[0]!, evidenceSegmentIds: ["missing"] }],
      }),
      "BLOCKED_EVIDENCE_MISSING",
    ],
    [
      "evidence",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        claims: [{ ...value.claims[0]!, evidenceText: "存在しない発言" }],
      }),
      "BLOCKED_EVIDENCE_TEXT_MISMATCH",
    ],
    [
      "confidence",
      (value: ReturnType<typeof validAnalysis>) => ({
        ...value,
        claims: [{ ...value.claims[0]!, confidence: 0.2 }],
      }),
      "BLOCKED_CONFIDENCE_LOW",
    ],
  ])("blocks semantically unsafe %s analysis", (_name, mutate, blockCode) => {
    const transcript = normalizeTranscript(document);
    const value = mutate(validAnalysis(transcript.segments[0]!.segmentKey));
    const result = validateTranscriptAnalysis(value, {
      expectedCharacterId: "raiden-shogun",
      knownEntityIds: new Set(["the-catch"]),
      transcript,
    });
    expect(result).toMatchObject({ ok: false, blockCode });
  });

  it("classifies provider failures and stops finite retries", async () => {
    expect(classifyProviderHttpStatus("x", 429)).toMatchObject({
      safeCode: "RATE_LIMITED",
      retryable: true,
      opensCircuit: true,
    });
    expect(classifyProviderHttpStatus("x", 503)).toMatchObject({
      safeCode: "UPSTREAM_5XX",
      retryable: true,
    });
    expect(
      toSafeProviderError(
        "x",
        new DOMException("provider body must not be copied", "AbortError"),
      ),
    ).toMatchObject({ safeCode: "TIMEOUT", retryable: true });
    let calls = 0;
    const sleeps: number[] = [];
    const result = await runWithFiniteRetry({
      maxAttempts: 3,
      operation: async () => {
        calls += 1;
        throw new SafeProviderError("fixture", "TIMEOUT", true, true);
      },
      sleep: async (milliseconds) => {
        sleeps.push(milliseconds);
      },
    });
    expect(result).toMatchObject({ ok: false, attempts: 3, exhausted: true });
    expect(calls).toBe(3);
    expect(sleeps).toEqual([30_000, 60_000]);
  });

  it("rejects invalid provider JSON without embedding the response", async () => {
    const provider = new GeminiTranscriptAnalysisProvider({
      apiKey: "test-only-key",
      fetchImpl: vi.fn(async () =>
        new Response(
          JSON.stringify({
            candidates: [{ content: { parts: [{ text: "{invalid" }] } }],
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      ) as typeof fetch,
    });
    await expect(
      provider.analyze({
        videoId: "video_12345",
        characterId: "raiden-shogun",
        language: "ja",
        chunks: [],
        allowedEntityIds: ["the-catch"],
      }),
    ).rejects.toMatchObject({
      safeCode: "INVALID_RESPONSE",
      retryable: false,
      message: "gemini-transcript-strict-v1:INVALID_RESPONSE",
    });
  });

  it("filters non-allowlisted, live, short, and unresolved discovery candidates", () => {
    const approved = new Set(["approved-channel"]);
    const hints = [{ id: "raiden-shogun", name: "雷電将軍" }];
    expect(
      evaluateDiscoveryCandidate({
        video: video(),
        approvedChannelIds: approved,
        characterHints: hints,
      }),
    ).toMatchObject({ eligible: true, characterId: "raiden-shogun" });
    expect(
      evaluateDiscoveryCandidate({
        video: video({ channelId: "other" }),
        approvedChannelIds: approved,
        characterHints: hints,
      }),
    ).toMatchObject({
      eligible: false,
      blockCode: "DISCOVERY_CHANNEL_NOT_APPROVED",
    });
    expect(
      evaluateDiscoveryCandidate({
        video: video({ liveBroadcastContent: "live" }),
        approvedChannelIds: approved,
        characterHints: hints,
      }),
    ).toMatchObject({
      eligible: false,
      blockCode: "DISCOVERY_LIVE_OR_PREMIERE",
    });
    expect(
      evaluateDiscoveryCandidate({
        video: video({ durationSeconds: 60 }),
        approvedChannelIds: approved,
        characterHints: hints,
      }),
    ).toMatchObject({
      eligible: false,
      blockCode: "DISCOVERY_POTENTIAL_SHORT",
    });
  });

  it("rejects valid JSON containing unknown keys before semantic validation", () => {
    const parsed = transcriptAnalysisSchema.safeParse({
      ...validAnalysis("segment"),
      providerReasoning: "must not be persisted",
    });
    expect(parsed.success).toBe(false);
  });
});

function validAnalysis(segmentId: string) {
  return {
    schemaVersion: "transcript-analysis-v1" as const,
    characterId: "raiden-shogun",
    overallConfidence: 0.96,
    claims: [
      {
        claimId: "weapon-1",
        kind: "weapon" as const,
        entityId: "the-catch",
        slot: null,
        value: "漁獲",
        condition: "",
        confidence: 0.95,
        evidenceSegmentIds: [segmentId],
        evidenceText: "漁獲がおすすめです",
      },
    ],
  };
}

function video(
  override: Partial<YoutubeVideoInfo> = {},
): YoutubeVideoInfo {
  return {
    videoId: "video_12345",
    channelId: "approved-channel",
    title: "【原神】「雷電将軍」おすすめ武器・聖遺物 完全育成ガイド",
    description: "",
    publishedAt: new Date("2026-07-31T00:00:00.000Z"),
    thumbnailUrl: "",
    sourceUrl: "https://www.youtube.com/watch?v=video_12345",
    metadataHash: "meta",
    durationSeconds: 600,
    privacyStatus: "public",
    language: "ja",
    liveBroadcastContent: "none",
    ...override,
  };
}
