import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { prisma } from "@/lib/db";
import { setYoutubeAutomationEmergencyStop } from "@/lib/build-guides/automation/admin-overview";
import type { DiscoveredGuideCandidate } from "@/lib/build-guides/automation/discovery-service";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import { automationHash } from "@/lib/build-guides/automation/idempotency";
import { runYoutubeGuidePipeline } from "@/lib/build-guides/automation/pipeline-runner";
import { SafeProviderError } from "@/lib/build-guides/automation/provider-error";
import type {
  TranscriptAnalysisProvider,
} from "@/lib/build-guides/automation/transcript-analysis-provider";
import { normalizeTranscript } from "@/lib/build-guides/automation/transcript-normalize";
import type {
  TranscriptDocument,
  TranscriptProvider,
  TranscriptTrack,
} from "@/lib/build-guides/automation/transcript-provider";
import type { YoutubeVideoInfo } from "@/lib/build-guides/youtube-client";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTAUDITRUNNER0000001";
let sequence = 0;

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

describe.runIf(runDbTests).sequential(
  "YouTube automation audit runner",
  () => {
    beforeAll(async () => {
      await cleanup();
      await setStop(false);
      await prisma.guideChannel.create({
        data: {
          channelId,
          title: "Audit runner",
          enabled: true,
          permissionStatus: "approved_for_processing",
        },
      });
    });

    afterAll(async () => {
      await setStop(false);
      await cleanup();
      await prisma.$disconnect();
    });

    it("lets only the item-lease winner call providers and publish", async () => {
      await setStop(false);
      const fixture = await createCandidate("concurrent", "audit-concurrent");
      const transcript = new CountingTranscriptProvider(fixture.document, 30);
      const analysis = new CountingAnalysisProvider(
        "audit-analysis-concurrent-v1",
        validAnalysis(fixture),
      );
      const run = (suffix: string) =>
        runYoutubeGuidePipeline({
          pipelineRunId: `audit-concurrent-${suffix}`,
          trigger: "test",
          dryRun: false,
          flags,
          discover: async () => [fixture.candidate],
          transcriptProvider: transcript,
          analysisProvider: analysis,
          loadKnownEntityIds: async () => new Set(["the-catch"]),
          now: new Date("2026-07-31T03:00:00.000Z"),
          workerId: `worker-${suffix}`,
        });
      await Promise.all([run("a"), run("b")]);
      expect(transcript.listCalls).toBe(1);
      expect(transcript.fetchCalls).toBe(1);
      expect(analysis.calls).toBe(1);
      await expect(
        prisma.characterBuildRecommendation.count({
          where: {
            characterId: fixture.characterId,
            status: "published",
          },
        }),
      ).resolves.toBe(1);
      await expect(
        prisma.guideVisualAnalysisResult.count({
          where: { videoId: fixture.video.videoId },
        }),
      ).resolves.toBe(1);
    });

    it("runs pass one for two same-run videos and reviews both in pass two", async () => {
      await setStop(false);
      const first = await createCandidate(
        "same-run-a",
        "audit-same-run-character",
      );
      const second = await createCandidate(
        "same-run-b",
        "audit-same-run-character",
      );
      const transcript = new FixtureTranscriptProvider([first, second]);
      const analysis = new FixtureAnalysisProvider(
        "audit-analysis-same-run-v1",
        [first, second],
      );
      const result = await runYoutubeGuidePipeline({
        pipelineRunId: "audit-same-run-multi",
        trigger: "test",
        dryRun: false,
        flags,
        discover: async () => [first.candidate, second.candidate],
        transcriptProvider: transcript,
        analysisProvider: analysis,
        loadKnownEntityIds: async () => new Set(["the-catch"]),
        now: new Date("2026-07-31T03:30:00.000Z"),
      });
      expect(result).toMatchObject({
        discovered: 2,
        published: 0,
        reviewRequired: 2,
      });
      expect(transcript.fetchCalls).toBe(2);
      expect(analysis.calls).toBe(2);
      await expect(
        prisma.guidePipelineItem.count({
          where: {
            characterId: "audit-same-run-character",
            status: "REVIEW_REQUIRED",
            blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
          },
        }),
      ).resolves.toBe(2);
      await expect(
        prisma.characterBuildRecommendation.count({
          where: { characterId: "audit-same-run-character" },
        }),
      ).resolves.toBe(0);

      const unchangedTranscript = new CountingTranscriptProvider(first.document);
      const unchangedAnalysis = new CountingAnalysisProvider(
        "audit-analysis-same-run-v1",
        validAnalysis(first),
      );
      await expect(
        runPipeline({
          runId: "audit-same-run-unchanged",
          fixture: first,
          transcript: unchangedTranscript,
          analysis: unchangedAnalysis,
          now: new Date("2026-07-31T03:31:00.000Z"),
        }),
      ).resolves.toMatchObject({ reviewRequired: 1, published: 0 });
      expect(unchangedTranscript.fetchCalls).toBe(1);
      expect(unchangedAnalysis.calls).toBe(0);

      const changedFirst = withTranscriptText(
        first,
        `漁獲がおすすめです 更新版 ${first.video.videoId}`,
      );
      const changedAnalysis = new CountingAnalysisProvider(
        "audit-analysis-same-run-v1",
        validAnalysis(changedFirst),
      );
      await expect(
        runPipeline({
          runId: "audit-same-run-changed",
          fixture: changedFirst,
          transcript: new CountingTranscriptProvider(changedFirst.document),
          analysis: changedAnalysis,
          now: new Date("2026-07-31T03:32:00.000Z"),
        }),
      ).resolves.toMatchObject({ reviewRequired: 1, published: 0 });
      expect(changedAnalysis.calls).toBe(1);
      await expect(
        prisma.guidePipelineItem.findUniqueOrThrow({
          where: { discoveryKey: first.candidate.discoveryKey },
          select: { transcriptHash: true, status: true },
        }),
      ).resolves.toEqual({
        transcriptHash: normalizeTranscript(changedFirst.document).transcriptHash,
        status: "REVIEW_REQUIRED",
      });
    });

    it("revalidates a published transcript hash before reuse and reanalyzes only changes", async () => {
      await setStop(false);
      const fixture = await createCandidate(
        "published-revalidation",
        "audit-published-revalidation",
      );
      await expect(
        runPipeline({
          runId: "audit-published-revalidation-first",
          fixture,
          transcript: new CountingTranscriptProvider(fixture.document),
          analysis: new CountingAnalysisProvider(
            "audit-analysis-revalidation-v1",
            validAnalysis(fixture),
          ),
          now: new Date("2026-07-31T03:33:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1 });
      const before =
        await prisma.characterBuildRecommendation.findFirstOrThrow({
          where: {
            characterId: fixture.characterId,
            status: "published",
          },
          include: { revisions: { orderBy: { createdAt: "asc" } } },
        });
      const beforeItem = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { discoveryKey: fixture.candidate.discoveryKey },
        select: { analysisIdempotencyKey: true },
      });

      const unchangedTranscript = new CountingTranscriptProvider(
        fixture.document,
      );
      const unchangedAnalysis = new CountingAnalysisProvider(
        "audit-analysis-revalidation-v1",
        validAnalysis(fixture),
      );
      await expect(
        runPipeline({
          runId: "audit-published-revalidation-unchanged",
          fixture,
          transcript: unchangedTranscript,
          analysis: unchangedAnalysis,
          now: new Date("2026-07-31T03:34:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1, blocked: 0, retryable: 0 });
      expect(unchangedTranscript.fetchCalls).toBe(1);
      expect(unchangedAnalysis.calls).toBe(0);
      const unchanged =
        await prisma.characterBuildRecommendation.findUniqueOrThrow({
          where: { id: before.id },
          include: { revisions: { orderBy: { createdAt: "asc" } } },
        });
      expect(unchanged.structuredPayload).toBe(before.structuredPayload);
      expect(unchanged.publishedAt?.toISOString()).toBe(
        before.publishedAt?.toISOString(),
      );
      expect(unchanged.updatedAt.toISOString()).toBe(
        before.updatedAt.toISOString(),
      );
      expect(unchanged.revisions.map(({ etag }) => etag)).toEqual(
        before.revisions.map(({ etag }) => etag),
      );

      const changed = withTranscriptText(
        fixture,
        `漁獲がおすすめです 改訂版 ${fixture.video.videoId}`,
      );
      const changedAnalysis = new CountingAnalysisProvider(
        "audit-analysis-revalidation-v1",
        validAnalysis(changed),
      );
      await expect(
        runPipeline({
          runId: "audit-published-revalidation-changed",
          fixture: changed,
          transcript: new CountingTranscriptProvider(changed.document),
          analysis: changedAnalysis,
          now: new Date("2026-07-31T03:35:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1, blocked: 0, retryable: 0 });
      expect(changedAnalysis.calls).toBe(1);
      const changedItem = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { discoveryKey: fixture.candidate.discoveryKey },
        select: {
          transcriptHash: true,
          analysisIdempotencyKey: true,
          status: true,
        },
      });
      expect(changedItem).toMatchObject({
        transcriptHash: normalizeTranscript(changed.document).transcriptHash,
        status: "PUBLISHED",
      });
      expect(changedItem.analysisIdempotencyKey).not.toBe(
        beforeItem.analysisIdempotencyKey,
      );
      await expect(
        prisma.guideVisualAnalysisResult.count({
          where: { videoId: fixture.video.videoId },
        }),
      ).resolves.toBe(2);
    });

    it("keeps the published snapshot unchanged when current transcript verification fails", async () => {
      await setStop(false);
      const fixture = await createCandidate(
        "published-unavailable",
        "audit-published-unavailable",
      );
      await expect(
        runPipeline({
          runId: "audit-published-unavailable-first",
          fixture,
          transcript: new CountingTranscriptProvider(fixture.document),
          analysis: new CountingAnalysisProvider(
            "audit-analysis-unavailable-v1",
            validAnalysis(fixture),
          ),
          now: new Date("2026-07-31T03:36:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1 });
      const before =
        await prisma.characterBuildRecommendation.findFirstOrThrow({
          where: {
            characterId: fixture.characterId,
            status: "published",
          },
          include: { revisions: { orderBy: { createdAt: "asc" } } },
        });

      await expect(
        runPipeline({
          runId: "audit-published-unavailable-failed",
          fixture,
          transcript: new UnavailableTranscriptProvider(),
          analysis: new CountingAnalysisProvider(
            "audit-analysis-unavailable-v1",
            validAnalysis(fixture),
          ),
          now: new Date("2026-07-31T03:37:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 0, blocked: 1, retryable: 0 });
      const after =
        await prisma.characterBuildRecommendation.findUniqueOrThrow({
          where: { id: before.id },
          include: { revisions: { orderBy: { createdAt: "asc" } } },
        });
      expect(after.structuredPayload).toBe(before.structuredPayload);
      expect(after.publishedAt?.toISOString()).toBe(
        before.publishedAt?.toISOString(),
      );
      expect(after.updatedAt.toISOString()).toBe(before.updatedAt.toISOString());
      expect(after.revisions.map(({ etag }) => etag)).toEqual(
        before.revisions.map(({ etag }) => etag),
      );
      await expect(
        prisma.guidePipelineItem.findUniqueOrThrow({
          where: { discoveryKey: fixture.candidate.discoveryKey },
          select: { status: true, blockCode: true },
        }),
      ).resolves.toEqual({
        status: "BLOCKED",
        blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE",
      });
    });

    it("keeps an earlier-run snapshot when the next run discovers another video", async () => {
      await setStop(false);
      const first = await createCandidate(
        "cross-run-a",
        "audit-cross-run-character",
      );
      const second = await createCandidate(
        "cross-run-b",
        "audit-cross-run-character",
      );
      await expect(
        runPipeline({
          runId: "audit-cross-run-a",
          fixture: first,
          transcript: new CountingTranscriptProvider(first.document),
          analysis: new CountingAnalysisProvider(
            "audit-analysis-cross-run-v1",
            validAnalysis(first),
          ),
          now: new Date("2026-07-31T03:40:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1 });
      const before =
        await prisma.characterBuildRecommendation.findFirstOrThrow({
          where: {
            characterId: "audit-cross-run-character",
            status: "published",
          },
          include: { revisions: true },
        });
      await expect(
        runPipeline({
          runId: "audit-cross-run-b",
          fixture: second,
          transcript: new CountingTranscriptProvider(second.document),
          analysis: new CountingAnalysisProvider(
            "audit-analysis-cross-run-v1",
            validAnalysis(second),
          ),
          now: new Date("2026-07-31T03:41:00.000Z"),
        }),
      ).resolves.toMatchObject({
        published: 0,
        reviewRequired: 1,
      });
      const after =
        await prisma.characterBuildRecommendation.findUniqueOrThrow({
          where: { id: before.id },
          include: { revisions: true },
        });
      expect(after.structuredPayload).toBe(before.structuredPayload);
      expect(after.publishedAt?.toISOString()).toBe(
        before.publishedAt?.toISOString(),
      );
      expect(after.revisions[0]?.etag).toBe(before.revisions[0]?.etag);
    });

    it("resumes a retry in a different run and preserves origin/current history", async () => {
      await setStop(false);
      const fixture = await createCandidate("resume", "audit-resume");
      const transcript = new CountingTranscriptProvider(fixture.document);
      const retrying = new ThrowingAnalysisProvider(
        "audit-analysis-resume-v1",
        new SafeProviderError(
          "audit-analysis-resume-v1",
          "RATE_LIMITED",
          true,
          true,
        ),
      );
      await expect(
        runPipeline({
          runId: "audit-resume-run-a",
          fixture,
          transcript,
          analysis: retrying,
          now: new Date("2026-07-31T04:00:00.000Z"),
        }),
      ).resolves.toMatchObject({ retryable: 1, published: 0 });
      const afterA = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { discoveryKey: fixture.candidate.discoveryKey },
      });
      expect(afterA.status).toBe("RETRYABLE_ERROR");
      expect(afterA.nextRetryAt?.toISOString()).toBe(
        "2026-07-31T04:00:30.000Z",
      );
      const runA = await prisma.guidePipelineRun.findUniqueOrThrow({
        where: { pipelineRunId: "audit-resume-run-a" },
      });
      expect(afterA.runId).toBe(runA.id);

      const succeeding = new CountingAnalysisProvider(
        "audit-analysis-resume-v1",
        validAnalysis(fixture),
      );
      await expect(
        runPipeline({
          runId: "audit-resume-run-b",
          fixture,
          transcript,
          analysis: succeeding,
          now: new Date("2026-07-31T04:01:00.000Z"),
        }),
      ).resolves.toMatchObject({ published: 1, retryable: 0 });
      const runB = await prisma.guidePipelineRun.findUniqueOrThrow({
        where: { pipelineRunId: "audit-resume-run-b" },
      });
      const afterB = await prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: afterA.id },
      });
      expect(afterB.runId).toBe(runA.id);
      expect(afterB.activeRunId).toBe(runB.id);
      expect(afterB.lastRunId).toBe(runB.id);
      expect(afterB.status).toBe("PUBLISHED");
      const eventRunIds = new Set(
        (
          await prisma.guidePipelineEvent.findMany({
            where: { itemId: afterA.id },
            select: { runId: true },
          })
        ).map(({ runId }) => runId),
      );
      expect(eventRunIds).toEqual(new Set([runA.id, runB.id]));

      const changedAnalyzer = new CountingAnalysisProvider(
        "audit-analysis-resume-v2",
        validAnalysis(fixture),
      );
      const changedResult = await runPipeline({
        runId: "audit-resume-run-c",
        fixture,
        transcript,
        analysis: changedAnalyzer,
        now: new Date("2026-07-31T04:02:00.000Z"),
      });
      expect(changedResult).toMatchObject({
        published: 1,
        reviewRequired: 0,
      });
      expect(changedAnalyzer.calls).toBe(1);
      await expect(
        prisma.guidePipelineItem.findUniqueOrThrow({
          where: { id: afterA.id },
          select: { analyzerVersion: true, status: true },
        }),
      ).resolves.toEqual({
        analyzerVersion: "audit-analysis-resume-v2",
        status: "PUBLISHED",
      });
    });

    it("blocks non-retryable provider auth errors instead of retrying", async () => {
      await setStop(false);
      const fixture = await createCandidate("auth", "audit-auth");
      const analysis = new ThrowingAnalysisProvider(
        "audit-analysis-auth-v1",
        new SafeProviderError(
          "audit-analysis-auth-v1",
          "AUTH_REJECTED",
          false,
        ),
      );
      const result = await runPipeline({
        runId: "audit-auth-run",
        fixture,
        transcript: new CountingTranscriptProvider(fixture.document),
        analysis,
        now: new Date("2026-07-31T05:00:00.000Z"),
      });
      expect(result).toMatchObject({ blocked: 1, retryable: 0 });
      await expect(
        prisma.guidePipelineItem.findUniqueOrThrow({
          where: { discoveryKey: fixture.candidate.discoveryKey },
          select: { status: true, blockCode: true, attempts: true },
        }),
      ).resolves.toEqual({
        status: "BLOCKED",
        blockCode: "BLOCKED_PROVIDER_AUTH",
        attempts: 0,
      });
    });

    it("stops before discovery with zero external calls", async () => {
      await setStop(false);
      const discover = vi.fn(async () => []);
      const loadKnown = vi.fn(async () => new Set<string>());
      const transcript = new CountingTranscriptProvider(
        emptyDocument("stopped0"),
      );
      const analysis = new CountingAnalysisProvider(
        "audit-analysis-stop-entry",
        {},
      );
      const result = await runYoutubeGuidePipeline({
        pipelineRunId: "audit-stop-before-discovery",
        trigger: "test",
        dryRun: false,
        flags,
        discover,
        transcriptProvider: transcript,
        analysisProvider: analysis,
        loadKnownEntityIds: loadKnown,
        testStageHook: async (stage) => {
          if (stage === "before_discovery") await setStop(true);
        },
      });
      expect(result).toMatchObject({ skipped: true, stopped: 1 });
      expect(discover).not.toHaveBeenCalled();
      expect(loadKnown).not.toHaveBeenCalled();
      expect(transcript.listCalls).toBe(0);
      expect(analysis.calls).toBe(0);
      await setStop(false);
    });

    it("rechecks stop before analysis and before publication", async () => {
      await setStop(false);
      const analysisFixture = await createCandidate(
        "stop-analysis",
        "audit-stop-analysis",
      );
      const analysis = new CountingAnalysisProvider(
        "audit-analysis-stop-analysis",
        validAnalysis(analysisFixture),
      );
      const analysisResult = await runPipeline({
        runId: "audit-stop-analysis-run",
        fixture: analysisFixture,
        transcript: new CountingTranscriptProvider(analysisFixture.document),
        analysis,
        now: new Date("2026-07-31T06:00:00.000Z"),
        hook: async (stage) => {
          if (stage === "before_analysis") await setStop(true);
        },
      });
      expect(analysisResult).toMatchObject({ stopped: 1, published: 0 });
      expect(analysis.calls).toBe(0);

      await setStop(false);
      const publishFixture = await createCandidate(
        "stop-publish",
        "audit-stop-publish",
      );
      const publishAnalysis = new CountingAnalysisProvider(
        "audit-analysis-stop-publish",
        validAnalysis(publishFixture),
      );
      const publishResult = await runPipeline({
        runId: "audit-stop-publish-run",
        fixture: publishFixture,
        transcript: new CountingTranscriptProvider(publishFixture.document),
        analysis: publishAnalysis,
        now: new Date("2026-07-31T06:01:00.000Z"),
        hook: async (stage) => {
          if (stage === "before_publish") await setStop(true);
        },
      });
      expect(publishResult).toMatchObject({ stopped: 1, published: 0 });
      expect(publishAnalysis.calls).toBe(1);
      await expect(
        prisma.characterBuildRecommendation.count({
          where: { characterId: publishFixture.characterId },
        }),
      ).resolves.toBe(0);
      await setStop(false);
    });

    it("fails closed when the singleton control row is missing", async () => {
      await prisma.guideAutomationControl.deleteMany({
        where: { id: "youtube-guide" },
      });
      const discover = vi.fn(async () => []);
      const result = await runYoutubeGuidePipeline({
        pipelineRunId: "audit-control-missing",
        trigger: "test",
        dryRun: false,
        flags,
        discover,
        transcriptProvider: new CountingTranscriptProvider(
          emptyDocument("missing0"),
        ),
        analysisProvider: new CountingAnalysisProvider(
          "audit-control-missing-analysis",
          {},
        ),
        loadKnownEntityIds: async () => new Set(),
      });
      expect(result).toMatchObject({ skipped: true, stopped: 1 });
      expect(discover).not.toHaveBeenCalled();
      await setStop(false);
    });
  },
);

function runPipeline(input: {
  runId: string;
  fixture: CandidateFixture;
  transcript: TranscriptProvider;
  analysis: TranscriptAnalysisProvider;
  now: Date;
  hook?: Parameters<typeof runYoutubeGuidePipeline>[0]["testStageHook"];
}) {
  return runYoutubeGuidePipeline({
    pipelineRunId: input.runId,
    trigger: "test",
    dryRun: false,
    flags,
    discover: async () => [input.fixture.candidate],
    transcriptProvider: input.transcript,
    analysisProvider: input.analysis,
    loadKnownEntityIds: async () => new Set(["the-catch"]),
    now: input.now,
    workerId: `${input.runId}-worker`,
    testStageHook: input.hook,
  });
}

type CandidateFixture = Awaited<ReturnType<typeof createCandidate>>;

async function createCandidate(label: string, characterId: string) {
  const token = ++sequence;
  const videoId = `runvid${token.toString().padStart(5, "0")}`;
  const video: YoutubeVideoInfo = {
    videoId,
    channelId,
    title: label,
    description: "",
    publishedAt: new Date("2026-07-31T00:00:00.000Z"),
    thumbnailUrl: "",
    sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
    metadataHash: automationHash("audit-runner-metadata", token),
    durationSeconds: 600,
    privacyStatus: "public",
    language: "ja",
    liveBroadcastContent: "none",
  };
  const document: TranscriptDocument = {
    providerId: "audit-transcript-v1",
    videoId,
    language: "ja",
    trackKind: "manual",
    sourceTrackId: `track-${token}`,
    fetchedAt: new Date("2026-07-31T00:00:00.000Z"),
    segments: [
      {
        startSeconds: 10,
        durationSeconds: 5,
        text: `漁獲がおすすめです ${videoId}`,
      },
    ],
  };
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
      availabilityStatus: "available",
    },
  });
  const candidate: DiscoveredGuideCandidate = {
    video,
    characterId,
    discoveryKey: automationHash("audit-runner-discovery", token),
    discoveryReason: "test",
  };
  return { video, characterId, document, candidate };
}

function validAnalysis(fixture: CandidateFixture) {
  const segmentId = normalizeTranscript(fixture.document).segments[0]!.segmentKey;
  return {
    schemaVersion: "transcript-analysis-v1",
    characterId: fixture.characterId,
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
  };
}

function withTranscriptText(
  fixture: CandidateFixture,
  text: string,
): CandidateFixture {
  return {
    ...fixture,
    document: {
      ...fixture.document,
      fetchedAt: new Date(fixture.document.fetchedAt.getTime() + 1),
      segments: [{ startSeconds: 10, durationSeconds: 5, text }],
    },
  };
}

class CountingTranscriptProvider implements TranscriptProvider {
  readonly providerId = "audit-transcript-v1";
  listCalls = 0;
  fetchCalls = 0;

  constructor(
    private readonly document: TranscriptDocument,
    private readonly delayMs = 0,
  ) {}

  async listTracks(): Promise<readonly TranscriptTrack[]> {
    this.listCalls += 1;
    if (this.delayMs > 0) {
      await new Promise<void>((resolve) => setTimeout(resolve, this.delayMs));
    }
    return [
      {
        trackId: this.document.sourceTrackId,
        language: this.document.language,
        trackKind: this.document.trackKind,
        isDraft: false,
      },
    ];
  }

  async fetchTrack(): Promise<TranscriptDocument> {
    this.fetchCalls += 1;
    return this.document;
  }
}

class UnavailableTranscriptProvider implements TranscriptProvider {
  readonly providerId = "audit-transcript-v1";

  async listTracks(): Promise<readonly TranscriptTrack[]> {
    return [];
  }

  async fetchTrack(): Promise<TranscriptDocument> {
    throw new Error("unexpectedTranscriptFetch");
  }
}

class CountingAnalysisProvider implements TranscriptAnalysisProvider {
  readonly supportsStrictSchema = true as const;
  calls = 0;

  constructor(
    readonly providerId: string,
    private readonly value: unknown,
  ) {}

  async analyze() {
    this.calls += 1;
    return {
      value: structuredClone(this.value),
      modelIdentifier: "deterministic",
      attempts: 1,
      usage: {},
    };
  }
}

class ThrowingAnalysisProvider implements TranscriptAnalysisProvider {
  readonly supportsStrictSchema = true as const;

  constructor(
    readonly providerId: string,
    private readonly error: Error,
  ) {}

  async analyze(): Promise<never> {
    throw this.error;
  }
}

class FixtureTranscriptProvider implements TranscriptProvider {
  readonly providerId = "audit-transcript-v1";
  fetchCalls = 0;
  private readonly documents: Map<string, TranscriptDocument>;

  constructor(fixtures: readonly CandidateFixture[]) {
    this.documents = new Map(
      fixtures.map((fixture) => [fixture.video.videoId, fixture.document]),
    );
  }

  async listTracks(videoId: string): Promise<readonly TranscriptTrack[]> {
    const document = this.documents.get(videoId);
    if (!document) return [];
    return [
      {
        trackId: document.sourceTrackId,
        language: document.language,
        trackKind: document.trackKind,
        isDraft: false,
      },
    ];
  }

  async fetchTrack(videoId: string): Promise<TranscriptDocument> {
    this.fetchCalls += 1;
    const document = this.documents.get(videoId);
    if (!document) throw new Error("fixtureTranscriptMissing");
    return document;
  }
}

class FixtureAnalysisProvider implements TranscriptAnalysisProvider {
  readonly supportsStrictSchema = true as const;
  calls = 0;
  private readonly fixtures: Map<string, CandidateFixture>;

  constructor(
    readonly providerId: string,
    fixtures: readonly CandidateFixture[],
  ) {
    this.fixtures = new Map(
      fixtures.map((fixture) => [fixture.video.videoId, fixture]),
    );
  }

  async analyze(input: { videoId: string }) {
    this.calls += 1;
    const fixture = this.fixtures.get(input.videoId);
    if (!fixture) throw new Error("fixtureAnalysisMissing");
    return {
      value: validAnalysis(fixture),
      modelIdentifier: "deterministic",
      attempts: 1,
      usage: {},
    };
  }
}

function emptyDocument(videoId: string): TranscriptDocument {
  return {
    providerId: "audit-transcript-v1",
    videoId,
    language: "ja",
    trackKind: "manual",
    sourceTrackId: "empty",
    fetchedAt: new Date(),
    segments: [{ startSeconds: 0, durationSeconds: 1, text: "fixture" }],
  };
}

async function setStop(value: boolean): Promise<void> {
  await setYoutubeAutomationEmergencyStop({
    emergencyStopped: value,
    reason: value ? "audit-test" : "",
  });
}

async function cleanup(): Promise<void> {
  await prisma.guidePipelineLease.deleteMany({
    where: {
      OR: [
        { lockKey: { startsWith: "pipeline-item:" } },
        { lockKey: { startsWith: "youtube-character-publication:audit-" } },
      ],
    },
  });
  await prisma.guideProviderCircuit.deleteMany({
    where: { providerId: { startsWith: "audit-" } },
  });
  await prisma.guideAdminAuditLog.deleteMany({
    where: { pipelineRunId: { startsWith: "audit-" } },
  });
  await prisma.characterBuildRecommendation.deleteMany({
    where: { characterId: { startsWith: "audit-" } },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: { pipelineRunId: { startsWith: "audit-" } },
  });
  await prisma.guideTranscript.deleteMany({
    where: { video: { channelId } },
  });
  await prisma.guideVideo.deleteMany({ where: { channelId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
