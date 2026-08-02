import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { runYoutubeGuidePipeline } from "@/lib/build-guides/automation/pipeline-runner";
import { getYoutubeAutomationAdminOverview } from "@/lib/build-guides/automation/admin-overview";
import { refreshPublishedSourceAvailability } from "@/lib/build-guides/automation/maintenance";
import { DeterministicTranscriptProvider } from "@/lib/build-guides/automation/testing-transcript-provider";
import { DeterministicTranscriptAnalysisProvider } from "@/lib/build-guides/automation/transcript-analysis-provider";
import { normalizeTranscript } from "@/lib/build-guides/automation/transcript-normalize";
import { deleteExpiredTranscripts } from "@/lib/build-guides/automation/transcript-store";
import {
  claimPipelineItem,
  releasePipelineItemClaim,
} from "@/lib/build-guides/automation/pipeline-item-lease";
import { automationHash } from "@/lib/build-guides/automation/idempotency";
import {
  buildPipelineRunSuccessResponse,
  parsePipelineRunSummary,
} from "@/lib/build-guides/automation/pipeline-summary";
import { getPublishedBuildRecommendationV2 } from "@/lib/build-guides/public-v2";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import type { YoutubeVideoInfo } from "@/lib/build-guides/youtube-client";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTPIPELINEPHASE500001";
const videoId = "phase5Video";
const pipelineRunId = "phase5-e2e-run";
const rawMarker = "RAW_TRANSCRIPT_RETENTION_MARKER_PHASE5";
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
      text: `雷電将軍には漁獲がおすすめです。${rawMarker}`,
    },
  ],
};

describe.runIf(runDbTests)("YouTube automation Phase 5 end-to-end PostgreSQL", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideAutomationControl.upsert({
      where: { id: "youtube-guide" },
      create: {
        id: "youtube-guide",
        emergencyStopped: false,
        reason: "",
      },
      update: { emergencyStopped: false, reason: "" },
    });
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
    const firstSummary = await run();
    expect(firstSummary).toMatchObject({
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
    const contribution =
      await prisma.recommendationVisualContribution.findFirstOrThrow({
        where: {
          recommendation: { characterId: "phase5-character" },
          videoId,
        },
      });
    expect(contribution.startSeconds).toBe(10);
    expect(contribution.endSeconds).toBe(15);
    const item = await prisma.guidePipelineItem.findUniqueOrThrow({
      where: { discoveryKey: "phase5-discovery-key" },
    });
    expect(item.transcriptHash).toBe(storedTranscript.transcriptHash);
    const storedRun = await prisma.guidePipelineRun.findUniqueOrThrow({
      where: { pipelineRunId },
      select: { summaryPayload: true },
    });
    const persistedSummary = parsePipelineRunSummary(storedRun.summaryPayload);
    expect(persistedSummary).toEqual(firstSummary);
    const jobSummary = formatActualJobSummary(
      buildPipelineRunSuccessResponse(persistedSummary),
    );
    expect(jobSummary).toContain('"published": 1');
    expect(jobSummary).not.toContain(rawMarker);

    const persistentStores = await Promise.all([
      prisma.guideChannel.findMany({ where: { channelId } }),
      prisma.guideVideo.findMany({ where: { videoId } }),
      prisma.guidePipelineRun.findMany({ where: { pipelineRunId } }),
      prisma.guideTranscript.findMany({ where: { videoId } }),
      prisma.guideTranscriptSegment.findMany({
        where: { transcript: { videoId } },
      }),
      prisma.guideVisualAnalysisResult.findMany({ where: { videoId } }),
      prisma.guideVisualEvidence.findMany({ where: { videoId } }),
      prisma.guidePipelineItem.findMany({ where: { videoId } }),
      prisma.guidePipelineEvent.findMany({ where: { itemId: item.id } }),
      prisma.characterBuildRecommendation.findMany({
        where: { characterId: "phase5-character" },
      }),
      prisma.guideRecommendationRevision.findMany({
        where: { pipelineRunId },
      }),
      prisma.recommendationVisualContribution.findMany({ where: { videoId } }),
      prisma.guideAdminAuditLog.findMany({ where: { pipelineRunId } }),
      prisma.guideProviderCircuit.findMany({
        where: {
          providerId: {
            in: [
              "deterministic-transcript-test-v1",
              "deterministic-transcript-analysis-test-v1",
            ],
          },
        },
      }),
      prisma.guidePipelineLease.findMany({
        where: { lockKey: { contains: "phase5" } },
      }),
      getPublishedBuildRecommendationV2("phase5-character"),
      getYoutubeAutomationAdminOverview(),
      jobSummary,
    ]);
    expect(JSON.stringify(persistentStores)).not.toContain(rawMarker);
    const analysisAfterCleanup =
      await prisma.guideVisualAnalysisResult.findFirstOrThrow({
        where: { videoId },
      });
    expect(analysisAfterCleanup.transcriptId).toBeNull();
    expect(analysisAfterCleanup.validatedPayload).not.toContain("evidenceText");
  });

  it("never copies provider payloads or error messages into persisted or job summaries", async () => {
    const transcriptProvider = new DeterministicTranscriptProvider(
      new Map([[videoId, transcriptDocument]]),
    );
    const unsafeAnalysisProvider = {
      providerId: "phase5-marker-analysis",
      supportsStrictSchema: true as const,
      async analyze() {
        return {
          value: {
            rawProviderResponse: rawMarker,
            error: { message: rawMarker },
          },
          modelIdentifier: "marker-fixture",
          attempts: 1,
          usage: {},
        };
      },
    };
    const providerSummary = await runYoutubeGuidePipeline({
      pipelineRunId: "phase5-summary-provider-marker",
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
      analysisProvider: unsafeAnalysisProvider,
      loadKnownEntityIds: async () => new Set(["the-catch"]),
      now: new Date("2026-08-01T01:00:00.000Z"),
    });
    expect(providerSummary).toMatchObject({ blocked: 1, published: 0 });

    const errorSummary = await runYoutubeGuidePipeline({
      pipelineRunId: "phase5-summary-error-marker",
      trigger: "test",
      dryRun: false,
      flags,
      discover: async () => {
        throw new Error(rawMarker);
      },
      transcriptProvider,
      analysisProvider: unsafeAnalysisProvider,
      loadKnownEntityIds: async () => new Set(["the-catch"]),
      now: new Date("2026-08-01T01:01:00.000Z"),
    });
    expect(errorSummary).toMatchObject({ retryable: 1 });

    const runs = await prisma.guidePipelineRun.findMany({
      where: { pipelineRunId: { startsWith: "phase5-summary-" } },
      select: { summaryPayload: true },
      orderBy: { pipelineRunId: "asc" },
    });
    expect(runs).toHaveLength(2);
    for (const run of runs) {
      expect(run.summaryPayload).not.toContain(rawMarker);
      const summary = parsePipelineRunSummary(run.summaryPayload);
      expect(summary).not.toBeNull();
      expect(
        formatActualJobSummary(buildPipelineRunSuccessResponse(summary)),
      ).not.toContain(rawMarker);
    }
  });

  it("keeps active, leased, and scheduled-retry transcripts", async () => {
    const active = await createExpiredFixture("active", "ANALYZING");
    const leased = await createExpiredFixture("leased", "BLOCKED");
    const retry = await createExpiredFixture("retry", "RETRYABLE_ERROR", {
      nextRetryAt: new Date("2026-08-02T00:00:00.000Z"),
    });
    const claim = await claimPipelineItem({
      itemId: leased.itemId,
      runDatabaseId: leased.runDatabaseId,
      pipelineRunId: leased.pipelineRunId,
      workerId: "cleanup-concurrency",
      now: new Date("2026-08-01T00:00:00.000Z"),
    });
    if (!claim) throw new Error("fixtureClaimFailed");
    try {
      await expect(
        deleteExpiredTranscripts({
          now: new Date("2026-08-01T00:00:00.000Z"),
          limit: 100,
        }),
      ).resolves.toBe(0);
      await expect(
        prisma.guideTranscript.count({
          where: {
            id: {
              in: [
                active.transcriptId,
                leased.transcriptId,
                retry.transcriptId,
              ],
            },
          },
        }),
      ).resolves.toBe(3);
    } finally {
      await releasePipelineItemClaim({ claim });
    }
    await expect(
      deleteExpiredTranscripts({
        now: new Date("2026-08-01T00:00:00.000Z"),
        limit: 100,
      }),
    ).resolves.toBe(1);
    await expect(
      prisma.guideTranscript.findUnique({
        where: { id: leased.transcriptId },
      }),
    ).resolves.toBeNull();
    await expect(
      prisma.guideTranscript.count({
        where: { id: { in: [active.transcriptId, retry.transcriptId] } },
      }),
    ).resolves.toBe(2);
  });
});

function formatActualJobSummary(response: unknown): string {
  const temp = mkdtempSync(join(tmpdir(), "phase5-job-summary-"));
  const responsePath = join(temp, "response.json");
  const outputPath = join(temp, "job-summary.md");
  writeFileSync(responsePath, JSON.stringify(response), "utf8");
  writeFileSync(outputPath, "", "utf8");
  execFileSync(
    process.execPath,
    [
      resolve(
        process.cwd(),
        "scripts",
        "format-youtube-guide-job-summary.mjs",
      ),
      responsePath,
      outputPath,
    ],
    { stdio: "pipe" },
  );
  return readFileSync(outputPath, "utf8");
}

async function createExpiredFixture(
  label: string,
  status: string,
  options: { nextRetryAt?: Date } = {},
) {
  const fixtureVideoId = `p5${label}video`;
  const fixtureRunId = `phase5-cleanup-${label}`;
  await prisma.guideVideo.create({
    data: {
      videoId: fixtureVideoId,
      channelId,
      title: label,
      privacyStatus: "public",
      metadataHash: automationHash("phase5-cleanup-meta", label),
      sourceUrl: `https://www.youtube.com/watch?v=${fixtureVideoId}`,
    },
  });
  const run = await prisma.guidePipelineRun.create({
    data: {
      pipelineRunId: fixtureRunId,
      idempotencyKey: automationHash("phase5-cleanup-run", label),
      trigger: "test",
      policyVersion: "cleanup",
      policyHash: automationHash("phase5-cleanup-policy", label),
    },
  });
  const transcript = await prisma.guideTranscript.create({
    data: {
      videoId: fixtureVideoId,
      identityKey: automationHash("phase5-cleanup-identity", label),
      transcriptHash: automationHash("phase5-cleanup-transcript", label),
      providerId: "phase5-cleanup",
      language: "ja",
      trackKind: "manual",
      sourceTrackId: label,
      segmentCount: 1,
      fetchedAt: new Date("2026-06-01T00:00:00.000Z"),
      retentionExpiresAt: new Date("2026-07-01T00:00:00.000Z"),
      segments: {
        create: {
          segmentIndex: 0,
          segmentKey: automationHash("phase5-cleanup-segment", label),
          startSeconds: 0,
          durationSeconds: 1,
          text: `${rawMarker}-${label}`,
          textHash: automationHash("phase5-cleanup-text", label),
        },
      },
    },
  });
  const item = await prisma.guidePipelineItem.create({
    data: {
      runId: run.id,
      lastRunId: run.id,
      videoId: fixtureVideoId,
      characterId: `phase5-cleanup-${label}`,
      discoveryKey: automationHash("phase5-cleanup-discovery", label),
      transcriptId: transcript.id,
      transcriptHash: transcript.transcriptHash,
      status,
      nextRetryAt: options.nextRetryAt,
    },
  });
  return {
    itemId: item.id,
    transcriptId: transcript.id,
    runDatabaseId: run.id,
    pipelineRunId: fixtureRunId,
  };
}

async function cleanup(): Promise<void> {
  await prisma.guideProviderCircuit.deleteMany({
    where: {
      providerId: {
        in: [
          "deterministic-transcript-test-v1",
          "deterministic-transcript-analysis-test-v1",
          "phase5-marker-analysis",
        ],
      },
    },
  });
  await prisma.guidePipelineLease.deleteMany({
    where: { lockKey: { contains: "phase5" } },
  });
  await prisma.guideAdminAuditLog.deleteMany({ where: { pipelineRunId } });
  await prisma.guideAdminAuditLog.deleteMany({
    where: { pipelineRunId: { startsWith: "phase5-summary-" } },
  });
  await prisma.guideAdminAuditLog.deleteMany({
    where: { pipelineRunId: { startsWith: "phase5-cleanup-" } },
  });
  await prisma.characterBuildRecommendation.deleteMany({
    where: { characterId: "phase5-character", verificationMode: "automatic_strict" },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: {
      OR: [
        { pipelineRunId },
        { pipelineRunId: { startsWith: "phase5-summary-" } },
        { pipelineRunId: { startsWith: "phase5-cleanup-" } },
      ],
    },
  });
  await prisma.guideVisualAnalysisResult.deleteMany({
    where: { video: { channelId } },
  });
  await prisma.guideTranscript.deleteMany({
    where: { video: { channelId } },
  });
  await prisma.guideVideo.deleteMany({ where: { channelId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
