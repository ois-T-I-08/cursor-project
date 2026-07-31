import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { runYoutubeGuidePipeline } from "@/lib/build-guides/automation/pipeline-runner";
import { refreshPublishedSourceAvailability } from "@/lib/build-guides/automation/maintenance";
import { DeterministicTranscriptProvider } from "@/lib/build-guides/automation/testing-transcript-provider";
import { DeterministicTranscriptAnalysisProvider } from "@/lib/build-guides/automation/transcript-analysis-provider";
import { normalizeTranscript } from "@/lib/build-guides/automation/transcript-normalize";
import { deleteExpiredTranscripts } from "@/lib/build-guides/automation/transcript-store";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import type { YoutubeVideoInfo } from "@/lib/build-guides/youtube-client";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTPIPELINEPHASE500001";
const videoId = "phase5Video";
const pipelineRunId = "phase5-e2e-run";
const flags: YoutubeAutomationFlags = {
  enabled: true,
  guideEnabled: true,
  discoveryEnabled: true,
  transcriptEnabled: true,
  analysisEnabled: true,
  geminiAnalysisEnabled: true,
  deepseekAnalysisEnabled: false,
  autoPublishEnabled: true,
  maintenanceEnabled: true,
};
const video: YoutubeVideoInfo = {
  videoId,
  channelId,
  title: "【原神】「雷電将軍」おすすめ武器 完全育成ガイド",
  description: "",
  publishedAt: new Date("2026-07-31T00:00:00.000Z"),
  thumbnailUrl: "",
  sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
  metadataHash: "phase5-metadata",
  durationSeconds: 600,
  privacyStatus: "public",
  language: "ja",
  liveBroadcastContent: "none",
};
const transcriptDocument = {
  providerId: "phase5-transcript",
  videoId,
  language: "ja",
  trackKind: "manual" as const,
  sourceTrackId: "phase5-track",
  fetchedAt: new Date("2026-07-31T00:00:00.000Z"),
  segments: [
    {
      startSeconds: 10,
      durationSeconds: 5,
      text: "雷電将軍には漁獲がおすすめです。",
    },
  ],
};

describe.runIf(runDbTests)("YouTube automation Phase 5 end-to-end PostgreSQL", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Phase 5 approved channel",
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    });
    await prisma.guideVideo.create({
      data: {
        videoId,
        channelId,
        title: video.title,
        publishedAt: video.publishedAt,
        durationSeconds: video.durationSeconds,
        privacyStatus: "public",
        metadataHash: video.metadataHash,
        sourceUrl: video.sourceUrl,
        language: "ja",
        discoveryReason: "test",
        availabilityStatus: "available",
      },
    });
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("runs discover through publish and reruns idempotently", async () => {
    const segmentId =
      normalizeTranscript(transcriptDocument).segments[0]!.segmentKey;
    const transcriptProvider = new DeterministicTranscriptProvider(
      new Map([[videoId, transcriptDocument]]),
    );
    const analysisProvider = new DeterministicTranscriptAnalysisProvider({
      schemaVersion: "transcript-analysis-v1",
      characterId: "phase5-character",
      overallConfidence: 0.96,
      claims: [
        {
          claimId: "weapon",
          kind: "weapon",
          entityId: "the-catch",
          slot: null,
          value: "漁獲",
          condition: "",
          confidence: 0.95,
          evidenceSegmentIds: [segmentId],
          evidenceText: "漁獲がおすすめです",
        },
      ],
    });
    const run = () =>
      runYoutubeGuidePipeline({
        pipelineRunId,
        trigger: "test",
        dryRun: false,
        flags,
        discover: async () => [
          {
            video,
            characterId: "phase5-character",
            discoveryKey: "phase5-discovery-key",
            discoveryReason: "test",
          },
        ],
        transcriptProvider,
        analysisProvider,
        loadKnownEntityIds: async () => new Set(["the-catch"]),
        now: new Date("2026-07-31T03:00:00.000Z"),
      });
    await expect(run()).resolves.toMatchObject({
      discovered: 1,
      published: 1,
      blocked: 0,
      retryable: 0,
    });
    await expect(run()).resolves.toMatchObject({
      discovered: 1,
      published: 1,
    });
    await expect(
      prisma.characterBuildRecommendation.count({
        where: { characterId: "phase5-character", verificationMode: "automatic_strict" },
      }),
    ).resolves.toBe(1);
    await expect(
      prisma.guideRecommendationRevision.count({
        where: { pipelineRunId },
      }),
    ).resolves.toBe(1);
    const storedTranscript = await prisma.guideTranscript.findFirstOrThrow({
      where: { videoId },
      include: { segments: true },
    });
    expect(storedTranscript.segments).toHaveLength(1);
    const audit = await prisma.guideAdminAuditLog.findFirstOrThrow({
      where: { pipelineRunId },
    });
    expect(audit.detail).not.toContain(transcriptDocument.segments[0]!.text);

    const availability = await refreshPublishedSourceAvailability({
      videoIds: [videoId],
      client: { fetchVideos: async () => [] },
      now: new Date("2026-08-01T00:00:00.000Z"),
    });
    expect(availability).toEqual({ checked: 1, unavailable: 1 });
    await expect(
      prisma.characterBuildRecommendation.count({
        where: { characterId: "phase5-character", status: "published" },
      }),
    ).resolves.toBe(1);

    await prisma.guideTranscript.update({
      where: { id: storedTranscript.id },
      data: { retentionExpiresAt: new Date("2026-07-01T00:00:00.000Z") },
    });
    await expect(
      deleteExpiredTranscripts({
        now: new Date("2026-08-01T00:00:00.000Z"),
      }),
    ).resolves.toBe(1);
    await expect(
      prisma.guideTranscriptSegment.count({
        where: { transcriptId: storedTranscript.id },
      }),
    ).resolves.toBe(0);
    await expect(
      prisma.characterBuildRecommendation.count({
        where: { characterId: "phase5-character", status: "published" },
      }),
    ).resolves.toBe(1);
  });
});

async function cleanup(): Promise<void> {
  await prisma.guideProviderCircuit.deleteMany({
    where: {
      providerId: {
        in: [
          "deterministic-transcript-test-v1",
          "deterministic-transcript-analysis-test-v1",
        ],
      },
    },
  });
  await prisma.guidePipelineLease.deleteMany({
    where: { lockKey: { contains: "phase5" } },
  });
  await prisma.guideAdminAuditLog.deleteMany({ where: { pipelineRunId } });
  await prisma.characterBuildRecommendation.deleteMany({
    where: { characterId: "phase5-character", verificationMode: "automatic_strict" },
  });
  await prisma.guidePipelineRun.deleteMany({ where: { pipelineRunId } });
  await prisma.guideVisualAnalysisResult.deleteMany({ where: { videoId } });
  await prisma.guideTranscript.deleteMany({ where: { videoId } });
  await prisma.guideVideo.deleteMany({ where: { videoId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
