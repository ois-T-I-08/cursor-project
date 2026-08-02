import { describe, expect, it, vi } from "vitest";
import { normalizePublicBuildRecommendation } from "@/lib/build-guides/public-recommendation-normalize";
import { publicBuildRecommendationSchema } from "@/lib/build-guides/visual-schemas";
import { publicBuildRecommendationV2Schema } from "@/lib/build-guides/public-v2";
import { mergeValidatedSourceAnalyses } from "@/lib/build-guides/automation/multi-source";
import { planSourceAvailability } from "@/lib/build-guides/automation/maintenance";
import type { YoutubeVideoInfo } from "@/lib/build-guides/youtube-client";

describe("YouTube automation Phase 4", () => {
  it("keeps schema v1 valid and validates the explicit v2 contract", () => {
    const v1 = v1Fixture();
    expect(publicBuildRecommendationSchema.parse(v1).schemaVersion).toBe(1);
    const v2 = publicBuildRecommendationV2Schema.parse({
      ...v1,
      schemaVersion: 2,
      verificationMode: "automatic_strict",
      sources: v1.sources.map((source) => ({
        ...source,
        availability: "unavailable",
        unavailableSince: "2026-07-31T01:00:00.000Z",
      })),
      evidence: [
        {
          fieldPath: "transcript",
          videoId: "phase4Video",
          timestampStart: 20,
          timestampEnd: 25,
        },
      ],
    });
    expect(v2.verificationMode).toBe("automatic_strict");
    expect(v2.sources[0]?.availability).toBe("unavailable");
    expect(v2.evidence[0]?.timestampStart).toBe(20);
    const serialized = JSON.stringify(v2);
    expect(serialized).not.toContain("secret transcript sentence");
    expect(serialized).not.toContain("exactVisibleText");
    expect(serialized).not.toContain("rawAiOutput");
  });

  it("serves v2 without exposing transcript content and supports ETag", async () => {
    const v1 = v1Fixture();
    const dto = publicBuildRecommendationV2Schema.parse({
      ...v1,
      schemaVersion: 2,
      verificationMode: "automatic_strict",
      sources: v1.sources.map((source) => ({
        ...source,
        availability: "available",
        unavailableSince: null,
      })),
      evidence: [
        {
          fieldPath: "transcript",
          videoId: "phase4Video",
          timestampStart: 20,
          timestampEnd: 25,
        },
      ],
    });
    vi.resetModules();
    vi.doMock("@/lib/build-guides/public-v2", () => ({
      getPublishedBuildRecommendationV2: async () => dto,
    }));
    const { GET } = await import(
      "../../app/api/v2/build-recommendations/[characterId]/route"
    );
    const response = await GET(
      new Request(
        "http://localhost/api/v2/build-recommendations/raiden-shogun",
      ),
      { params: Promise.resolve({ characterId: "raiden-shogun" }) },
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("etag")).toContain("br-v2-raiden-shogun");
    const body = (await response.json()) as { ok: boolean; data: unknown };
    expect(body.ok).toBe(true);
    expect(JSON.stringify(body.data)).not.toContain("exactVisibleText");

    const notModified = await GET(
      new Request(
        "http://localhost/api/v2/build-recommendations/raiden-shogun",
        { headers: { "if-none-match": response.headers.get("etag")! } },
      ),
      { params: Promise.resolve({ characterId: "raiden-shogun" }) },
    );
    expect(notModified.status).toBe(304);
  });

  it("keeps deterministic multi-source merges review-only", () => {
    const claim = {
      claimId: "weapon",
      kind: "weapon" as const,
      entityId: "the-catch",
      slot: null,
      value: "漁獲",
      condition: "",
      confidence: 0.95,
      evidenceSegmentIds: ["segment"],
      evidenceText: "internal",
      startSeconds: 10,
      endSeconds: 15,
    };
    const result = mergeValidatedSourceAnalyses([
      {
        analysisIdempotencyKey: "analysis-a",
        videoId: "video-a",
        characterId: "raiden-shogun",
        claims: [claim],
      },
      {
        analysisIdempotencyKey: "analysis-b",
        videoId: "video-b",
        characterId: "raiden-shogun",
        claims: [{ ...claim, evidenceSegmentIds: ["other"] }],
      },
    ]);
    expect(result).toMatchObject({
      status: "READY_TO_PUBLISH",
      automaticPublishAllowed: false,
      sourceCount: 2,
    });
  });

  it("marks missing or private sources unavailable without touching snapshots", () => {
    const plan = planSourceAvailability({
      requestedVideoIds: ["public-video", "private-video", "missing-video"],
      fetchedVideos: [
        video({ videoId: "public-video", privacyStatus: "public" }),
        video({ videoId: "private-video", privacyStatus: "private" }),
      ],
    });
    expect(plan).toEqual([
      {
        videoId: "missing-video",
        availabilityStatus: "unavailable",
        privacyStatus: "missing",
      },
      {
        videoId: "private-video",
        availabilityStatus: "unavailable",
        privacyStatus: "private",
      },
      {
        videoId: "public-video",
        availabilityStatus: "available",
        privacyStatus: "public",
      },
    ]);
  });
});

function v1Fixture() {
  const { data } = normalizePublicBuildRecommendation({
    characterId: "raiden-shogun",
    origin: "single_video",
    overallConfidence: 0.96,
    context: {},
    mainStats: [],
    substatPriority: [],
    targets: [],
    structured: {},
    caveats: [],
    lastVerifiedAt: "2026-07-31T00:00:00.000Z",
    publishedAt: "2026-07-31T00:00:00.000Z",
    updatedAt: "2026-07-31T00:00:00.000Z",
    sources: [
      {
        videoId: "phase4Video",
        title: "guide",
        channelTitle: "channel",
        sourceUrl: "https://www.youtube.com/watch?v=phase4Video",
      },
    ],
    evidence: [
      {
        fieldPath: "visual",
        exactVisibleText: "visible UI text",
        videoId: "phase4Video",
        startSeconds: 20,
        endSeconds: 25,
      },
    ],
  });
  return publicBuildRecommendationSchema.parse(data);
}

function video(override: Partial<YoutubeVideoInfo>): YoutubeVideoInfo {
  return {
    videoId: "phase4Video",
    channelId: "channel",
    title: "guide",
    description: "",
    publishedAt: null,
    thumbnailUrl: "",
    sourceUrl: "https://www.youtube.com/watch?v=phase4Video",
    metadataHash: "hash",
    durationSeconds: 600,
    privacyStatus: "public",
    language: "ja",
    liveBroadcastContent: "none",
    ...override,
  };
}
