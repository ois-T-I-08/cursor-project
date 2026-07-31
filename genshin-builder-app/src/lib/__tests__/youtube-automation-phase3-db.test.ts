import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { setYoutubeAutomationEmergencyStop } from "@/lib/build-guides/automation/admin-overview";
import {
  AUTOMATIC_PUBLISH_FAILURE_STAGES,
  publishAutomaticRecommendation,
} from "@/lib/build-guides/automation/auto-publish-store";
import { buildAutomaticRecommendationSnapshot } from "@/lib/build-guides/automation/automatic-snapshot";
import { canonicalizeValidatedAnalysis } from "@/lib/build-guides/automation/canonical-analysis";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";
import {
  analysisIdempotencyKey,
  automationHash,
  publicationKey,
} from "@/lib/build-guides/automation/idempotency";
import {
  claimPipelineItem,
  releasePipelineItemClaim,
} from "@/lib/build-guides/automation/pipeline-item-lease";
import { acquirePipelineLease } from "@/lib/build-guides/automation/lease-store";
import {
  YOUTUBE_AUTOMATION_POLICY,
  YOUTUBE_AUTOMATION_POLICY_HASH,
} from "@/lib/build-guides/automation/quality-policy";
import type { AnalysisValidationResult } from "@/lib/build-guides/automation/analysis-schema";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTPIPELINEPHASE300001";
const marker = "RAW_EVIDENCE_MARKER_PHASE3";
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

describe.runIf(runDbTests)("YouTube automation Phase 3 PostgreSQL", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideAutomationControl.upsert({
      where: { id: "youtube-guide" },
      create: { id: "youtube-guide", emergencyStopped: false, reason: "" },
      update: { emergencyStopped: false, reason: "" },
    });
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Approved Phase 3 Channel",
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    });
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("publishes one source and never persists raw evidence text", async () => {
    const seed = await seedReady("phase3-single");
    const claim = await claimSeed(seed, "worker-single");
    try {
      const result = await publishAutomaticRecommendation({
        pipelineRunId: seed.pipelineRunId,
        itemClaim: claim,
        flags,
        dryRun: false,
        now: seed.now,
      });
      expect(result).toMatchObject({ published: true, idempotent: false });
      const analysis =
        await prisma.guideVisualAnalysisResult.findUniqueOrThrow({
          where: { analysisIdempotencyKey: seed.analysisKey },
        });
      expect(analysis.validatedPayload).not.toContain(marker);
      expect(analysis.rawAiOutput).toBe("");
      expect(JSON.stringify(await loadPersistentText(seed))).not.toContain(
        marker,
      );
    } finally {
      await releasePipelineItemClaim({ claim });
    }
  });

  it("marks both same-run sources for review without publishing", async () => {
    const sharedRun = await createRun("phase3-same-run");
    const first = await seedReady("phase3-same-a", {
      characterId: "phase3-same-character",
      run: sharedRun,
    });
    const second = await seedReady("phase3-same-b", {
      characterId: "phase3-same-character",
      run: sharedRun,
    });
    const itemClaim = await claimSeed(first, "worker-same");
    try {
      const result = await publishAutomaticRecommendation({
        pipelineRunId: first.pipelineRunId,
        itemClaim,
        flags,
        dryRun: false,
        now: first.now,
      });
      expect(result).toEqual({
        published: false,
        status: "REVIEW_REQUIRED",
        blockCodes: ["MULTI_SOURCE_REVIEW_REQUIRED"],
      });
      const items = await prisma.guidePipelineItem.findMany({
        where: { id: { in: [first.itemId, second.itemId] } },
        orderBy: { videoId: "asc" },
        select: { status: true, blockCode: true },
      });
      expect(items).toEqual([
        {
          status: "REVIEW_REQUIRED",
          blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
        },
        {
          status: "REVIEW_REQUIRED",
          blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
        },
      ]);
      await expect(
        prisma.characterBuildRecommendation.count({
          where: { characterId: "phase3-same-character" },
        }),
      ).resolves.toBe(0);
    } finally {
      await releasePipelineItemClaim({ claim: itemClaim });
    }
  });

  it("keeps the existing snapshot and ETag when a later run finds a second video", async () => {
    const first = await seedReady("phase3-cross-a", {
      characterId: "phase3-cross-character",
    });
    const firstClaim = await claimSeed(first, "worker-cross-a");
    let publishedId = "";
    try {
      const result = await publishAutomaticRecommendation({
        pipelineRunId: first.pipelineRunId,
        itemClaim: firstClaim,
        flags,
        dryRun: false,
        now: first.now,
      });
      if (!result.published) throw new Error("fixturePublicationFailed");
      publishedId = result.recommendationId;
    } finally {
      await releasePipelineItemClaim({ claim: firstClaim });
    }
    const before =
      await prisma.characterBuildRecommendation.findUniqueOrThrow({
        where: { id: publishedId },
        include: { revisions: true },
      });
    const second = await seedReady("phase3-cross-b", {
      characterId: "phase3-cross-character",
    });
    const secondClaim = await claimSeed(second, "worker-cross-b");
    try {
      await expect(
        publishAutomaticRecommendation({
          pipelineRunId: second.pipelineRunId,
          itemClaim: secondClaim,
          flags,
          dryRun: false,
          now: second.now,
        }),
      ).resolves.toMatchObject({
        published: false,
        status: "REVIEW_REQUIRED",
        blockCodes: ["MULTI_SOURCE_REVIEW_REQUIRED"],
      });
    } finally {
      await releasePipelineItemClaim({ claim: secondClaim });
    }
    const after =
      await prisma.characterBuildRecommendation.findUniqueOrThrow({
        where: { id: publishedId },
        include: { revisions: true },
      });
    expect(after.structuredPayload).toBe(before.structuredPayload);
    expect(after.publishedAt?.toISOString()).toBe(
      before.publishedAt?.toISOString(),
    );
    expect(after.revisions).toHaveLength(1);
    expect(after.revisions[0]?.etag).toBe(before.revisions[0]?.etag);
    await expect(
      prisma.guidePipelineItem.findUniqueOrThrow({
        where: { id: second.itemId },
        select: { status: true, blockCode: true },
      }),
    ).resolves.toEqual({
      status: "REVIEW_REQUIRED",
      blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
    });
  });

  it("serializes concurrent multi-source publishers and reviews both items", async () => {
    const sharedRun = await createRun("phase3-concurrent-multi");
    const first = await seedReady("phase3-concurrent-a", {
      characterId: "phase3-concurrent-character",
      run: sharedRun,
    });
    const second = await seedReady("phase3-concurrent-b", {
      characterId: "phase3-concurrent-character",
      run: sharedRun,
    });
    const firstClaim = await claimSeed(first, "worker-concurrent-a");
    const secondClaim = await claimSeed(second, "worker-concurrent-b");
    try {
      const results = await Promise.all([
        publishAutomaticRecommendation({
          pipelineRunId: first.pipelineRunId,
          itemClaim: firstClaim,
          flags,
          dryRun: false,
          now: first.now,
        }),
        publishAutomaticRecommendation({
          pipelineRunId: second.pipelineRunId,
          itemClaim: secondClaim,
          flags,
          dryRun: false,
          now: second.now,
        }),
      ]);
      expect(
        results.some(
          (result) =>
            !result.published && result.status === "REVIEW_REQUIRED",
        ),
      ).toBe(true);
      await expect(
        prisma.guidePipelineItem.count({
          where: {
            id: { in: [first.itemId, second.itemId] },
            status: "REVIEW_REQUIRED",
            blockCode: "MULTI_SOURCE_REVIEW_REQUIRED",
          },
        }),
      ).resolves.toBe(2);
      await expect(
        prisma.characterBuildRecommendation.count({
          where: { characterId: "phase3-concurrent-character" },
        }),
      ).resolves.toBe(0);
    } finally {
      await releasePipelineItemClaim({ claim: firstClaim });
      await releasePipelineItemClaim({ claim: secondClaim });
    }
  });

  it("holds the character lease from source count through commit", async () => {
    const seed = await seedReady("phase3-source-race", {
      characterId: "phase3-source-race-character",
    });
    const itemClaim = await claimSeed(seed, "worker-source-race");
    const counted = deferred();
    const release = deferred();
    try {
      const publication = publishAutomaticRecommendation({
        pipelineRunId: seed.pipelineRunId,
        itemClaim,
        flags,
        dryRun: false,
        now: seed.now,
        transactionStageHook: async (stage) => {
          if (stage !== "source_recalculated") return;
          counted.resolve();
          await release.promise;
        },
      });
      await counted.promise;
      const insertionLease = await acquirePipelineLease({
        lockKey:
          "youtube-character-publication:phase3-source-race-character",
        leaseOwner: "late-candidate-materializer",
        now: seed.now,
        ttlMs: 60_000,
      });
      expect(insertionLease).toBeNull();
      release.resolve();
      await expect(publication).resolves.toMatchObject({ published: true });
    } finally {
      release.resolve();
      await releasePipelineItemClaim({ claim: itemClaim });
    }
  });

  it("linearizes emergency stop with the same control-row lock", async () => {
    await setStop(false);
    const seed = await seedReady("phase3-stop-linearized", {
      characterId: "phase3-stop-linearized-character",
    });
    const itemClaim = await claimSeed(seed, "worker-stop-linearized");
    const locked = deferred();
    const release = deferred();
    try {
      const publication = publishAutomaticRecommendation({
        pipelineRunId: seed.pipelineRunId,
        itemClaim,
        flags,
        dryRun: false,
        now: seed.now,
        transactionStageHook: async (stage) => {
          if (stage !== "control_locked") return;
          locked.resolve();
          await release.promise;
        },
      });
      await locked.promise;
      let stopCommitted = false;
      const stop = setStop(true).then(() => {
        stopCommitted = true;
      });
      await new Promise<void>((resolve) => setTimeout(resolve, 25));
      expect(stopCommitted).toBe(false);
      release.resolve();
      await expect(publication).resolves.toMatchObject({ published: true });
      await stop;
      expect(stopCommitted).toBe(true);
    } finally {
      release.resolve();
      await setStop(false);
      await releasePipelineItemClaim({ claim: itemClaim });
    }
  });

  it("rejects publication when stop or the control row is already committed", async () => {
    for (const condition of ["stopped", "missing"] as const) {
      await setStop(false);
      const seed = await seedReady(`phase3-control-${condition}`, {
        characterId: `phase3-control-${condition}-character`,
      });
      const itemClaim = await claimSeed(seed, `worker-${condition}`);
      try {
        if (condition === "stopped") await setStop(true);
        else {
          await prisma.guideAutomationControl.delete({
            where: { id: "youtube-guide" },
          });
        }
        await expect(
          publishAutomaticRecommendation({
            pipelineRunId: seed.pipelineRunId,
            itemClaim,
            flags,
            dryRun: false,
            now: seed.now,
          }),
        ).resolves.toMatchObject({
          published: false,
          status: "STOPPED",
        });
        await expect(
          prisma.characterBuildRecommendation.count({
            where: { publicationKey: seed.publicationKey },
          }),
        ).resolves.toBe(0);
      } finally {
        await setStop(false);
        await releasePipelineItemClaim({ claim: itemClaim });
      }
    }
  });

  it.each(AUTOMATIC_PUBLISH_FAILURE_STAGES)(
    "rolls back every publish write when failure is injected at %s",
    async (stage) => {
      const seed = await seedReady(`phase3-rollback-${stage}`, {
        characterId: `phase3-rollback-${stage}`,
      });
      const itemClaim = await claimSeed(seed, `worker-${stage}`);
      try {
        await expect(
          publishAutomaticRecommendation({
            pipelineRunId: seed.pipelineRunId,
            itemClaim,
            flags,
            dryRun: false,
            now: seed.now,
            failureInjection: (current) => {
              if (current === stage) throw new Error(`injected:${stage}`);
            },
          }),
        ).rejects.toThrow(`injected:${stage}`);
        await expect(
          prisma.characterBuildRecommendation.count({
            where: { publicationKey: seed.publicationKey },
          }),
        ).resolves.toBe(0);
        await expect(
          prisma.guideVisualAnalysisResult.count({
            where: { analysisIdempotencyKey: seed.analysisKey },
          }),
        ).resolves.toBe(0);
        await expect(
          prisma.guideRecommendationRevision.count({
            where: { publicationKey: seed.publicationKey },
          }),
        ).resolves.toBe(0);
        await expect(
          prisma.guideAdminAuditLog.count({
            where: {
              pipelineRunId: seed.pipelineRunId,
              action: "automatic_publish",
            },
          }),
        ).resolves.toBe(0);
        await expect(
          prisma.recommendationVisualContribution.count({
            where: { recommendation: { publicationKey: seed.publicationKey } },
          }),
        ).resolves.toBe(0);
        await expect(
          prisma.guidePipelineItem.findUniqueOrThrow({
            where: { id: seed.itemId },
            select: { status: true },
          }),
        ).resolves.toEqual({ status: "READY_TO_PUBLISH" });
      } finally {
        await releasePipelineItemClaim({ claim: itemClaim });
      }
    },
  );
});

type Seed = Awaited<ReturnType<typeof seedReady>>;

async function claimSeed(seed: Seed, workerId: string) {
  const itemClaim = await claimPipelineItem({
    itemId: seed.itemId,
    runDatabaseId: seed.runDatabaseId,
    pipelineRunId: seed.pipelineRunId,
    workerId,
    now: seed.now,
  });
  if (!itemClaim) throw new Error("fixtureClaimFailed");
  return itemClaim;
}

async function createRun(label: string) {
  const id = `${label}-${++sequence}`;
  return prisma.guidePipelineRun.create({
    data: {
      pipelineRunId: id,
      idempotencyKey: automationHash("phase3-run", id),
      trigger: "test",
      mode: "automatic",
      dryRun: false,
      policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
      policyHash: YOUTUBE_AUTOMATION_POLICY_HASH,
    },
  });
}

async function seedReady(
  label: string,
  options: {
    characterId?: string;
    run?: Awaited<ReturnType<typeof createRun>>;
  } = {},
) {
  const token = ++sequence;
  const videoId = `p3video${token.toString().padStart(4, "0")}`;
  const characterId = options.characterId ?? `${label}-character`;
  const run = options.run ?? (await createRun(label));
  const now = new Date("2026-07-31T01:00:00.000Z");
  const metadataHash = automationHash("phase3-metadata", { label, token });
  const transcriptHash = automationHash("phase3-transcript", {
    label,
    token,
  });
  const analysisKey = analysisIdempotencyKey({
    videoId,
    metadataHash,
    transcriptHash,
    analyzerVersion: "phase3-analyzer-v2",
    promptVersion: "youtube-transcript-claims-v1",
    schemaVersion: "transcript-analysis-v1",
  });
  const validation: Extract<AnalysisValidationResult, { ok: true }> = {
    ok: true,
    analysis: {
      schemaVersion: "transcript-analysis-v1",
      characterId,
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
          evidenceSegmentIds: ["segment-1"],
          evidenceText: marker,
        },
      ],
    },
    claims: [
      {
        claimId: "weapon",
        kind: "weapon",
        entityId: "the-catch",
        slot: null,
        value: "漁獲",
        condition: "",
        confidence: 0.95,
        evidenceSegmentIds: ["segment-1"],
        evidenceText: marker,
        startSeconds: 10,
        endSeconds: 25,
      },
    ],
    quality: {
      claimCount: 1,
      citationCoverage: 1,
      timestampCoverage: 1,
      entityCoverage: 1,
      minClaimConfidence: 0.95,
      overallConfidence: 0.96,
    },
  };
  const canonical = canonicalizeValidatedAnalysis({
    validation,
    transcriptHash,
    analysisIdempotencyKey: analysisKey,
    providerId: "phase3-analyzer-v2",
    modelIdentifier: "deterministic",
    promptVersion: "youtube-transcript-claims-v1",
  });
  const publication = publicationKey({
    characterId,
    analysisKeys: [analysisKey],
    policyVersion: YOUTUBE_AUTOMATION_POLICY.version,
    schemaVersion: "transcript-analysis-v1",
  });
  const snapshot = buildAutomaticRecommendationSnapshot({
    characterId,
    videoId,
    claims: canonical.canonical.claims,
    overallConfidence: 0.96,
    publishedContentUpdatedAt: now,
  });
  await prisma.guideVideo.create({
    data: {
      videoId,
      channelId,
      title: label,
      privacyStatus: "public",
      availabilityStatus: "available",
      metadataHash,
      sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
    },
  });
  const transcript = await prisma.guideTranscript.create({
    data: {
      videoId,
      identityKey: automationHash("phase3-transcript-identity", {
        label,
        token,
      }),
      transcriptHash,
      providerId: "phase3-transcript",
      language: "ja",
      trackKind: "manual",
      sourceTrackId: `track-${token}`,
      segmentCount: 1,
      fetchedAt: now,
    },
  });
  const item = await prisma.guidePipelineItem.create({
    data: {
      runId: run.id,
      lastRunId: run.id,
      videoId,
      characterId,
      discoveryKey: automationHash("phase3-discovery", { label, token }),
      analysisIdempotencyKey: analysisKey,
      publicationKey: publication,
      transcriptId: transcript.id,
      status: "READY_TO_PUBLISH",
      metadataHash,
      transcriptHash,
      analyzerVersion: "phase3-analyzer-v2",
      promptVersion: "youtube-transcript-claims-v1",
      schemaVersion: "transcript-analysis-v1",
      qualityPayload: JSON.stringify({
        channelAllowed: true,
        videoPublic: true,
        transcriptAvailable: true,
        schemaValid: true,
        entityCoverage: 1,
        citationCoverage: 1,
        timestampCoverage: 1,
        evidenceMatches: true,
        minClaimConfidence: 0.95,
        overallConfidence: 0.96,
        conflicts: [],
      }),
      canonicalAnalysisPayload: canonical.payload,
      validationHash: canonical.validationHash,
      snapshotPayload: JSON.stringify(snapshot),
      policyHash: YOUTUBE_AUTOMATION_POLICY_HASH,
    },
  });
  return {
    itemId: item.id,
    videoId,
    characterId,
    pipelineRunId: run.pipelineRunId,
    runDatabaseId: run.id,
    publicationKey: publication,
    analysisKey,
    now,
  };
}

async function loadPersistentText(seed: Seed) {
  return Promise.all([
    prisma.guidePipelineEvent.findMany({
      where: { itemId: seed.itemId },
    }),
    prisma.guideAdminAuditLog.findMany({
      where: { pipelineRunId: seed.pipelineRunId },
    }),
    prisma.guideRecommendationRevision.findMany({
      where: { publicationKey: seed.publicationKey },
    }),
    prisma.characterBuildRecommendation.findMany({
      where: { publicationKey: seed.publicationKey },
    }),
  ]);
}

async function cleanup(): Promise<void> {
  await prisma.guidePipelineLease.deleteMany({
    where: {
      OR: [
        { lockKey: { startsWith: "pipeline-item:" } },
        { lockKey: { startsWith: "youtube-character-publication:" } },
      ],
    },
  });
  await prisma.guideAdminAuditLog.deleteMany({
    where: { pipelineRunId: { startsWith: "phase3-" } },
  });
  await prisma.characterBuildRecommendation.deleteMany({
    where: { characterId: { startsWith: "phase3-" } },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: { pipelineRunId: { startsWith: "phase3-" } },
  });
  await prisma.guideTranscript.deleteMany({
    where: { video: { channelId } },
  });
  await prisma.guideVideo.deleteMany({ where: { channelId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}

async function setStop(emergencyStopped: boolean): Promise<void> {
  await setYoutubeAutomationEmergencyStop({
    emergencyStopped,
    reason: emergencyStopped ? "phase3-test" : "",
  });
}

function deferred(): {
  promise: Promise<void>;
  resolve: () => void;
} {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
