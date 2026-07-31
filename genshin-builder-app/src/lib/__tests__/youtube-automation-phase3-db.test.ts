import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { publishAutomaticRecommendation } from "@/lib/build-guides/automation/auto-publish-store";
import { buildAutomaticRecommendationSnapshot } from "@/lib/build-guides/automation/automatic-snapshot";
import { getPublishedBuildRecommendation } from "@/lib/build-guides/store";
import type { YoutubeAutomationFlags } from "@/lib/build-guides/automation/feature-flags";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTPIPELINEPHASE300001";
const videoId = "phase3Video";
const pipelineRunId = "phase3-run";
const publicationKey = "phase3-publication";
const analysisKey = "phase3-analysis";
let itemId = "";
let evidenceId = "";

const flags: YoutubeAutomationFlags = {
  enabled: true,
  discoveryEnabled: true,
  transcriptEnabled: true,
  analysisEnabled: true,
  autoPublishEnabled: true,
  maintenanceEnabled: true,
};
const quality = {
  sourceCount: 1,
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
} as const;

describe.runIf(runDbTests)("YouTube automation Phase 3 PostgreSQL", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Approved Phase 3 Channel",
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    });
    await prisma.guideVideo.create({
      data: {
        videoId,
        channelId,
        title: "【原神】「雷電将軍」完全育成ガイド",
        privacyStatus: "public",
        availabilityStatus: "available",
        metadataHash: "phase3-meta",
        sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
      },
    });
    const run = await prisma.guidePipelineRun.create({
      data: {
        pipelineRunId,
        idempotencyKey: "phase3-run-key",
        trigger: "test",
        mode: "automatic",
        dryRun: false,
        policyVersion: "v1",
        policyHash: "hash",
      },
    });
    const item = await prisma.guidePipelineItem.create({
      data: {
        runId: run.id,
        videoId,
        discoveryKey: "phase3-discovery",
        analysisIdempotencyKey: analysisKey,
        publicationKey,
        status: "READY_TO_PUBLISH",
      },
    });
    itemId = item.id;
    const analysis = await prisma.guideVisualAnalysisResult.create({
      data: {
        cacheKey: "phase3-analysis-cache",
        videoId,
        requestHash: "phase3-request",
        providerId: "deterministic",
        modelIdentifier: "deterministic",
        promptVersion: "v1",
        schemaVersion: "transcript-analysis-v1",
        gameDataVersion: "master-v1",
        inputKind: "transcript",
        analysisIdempotencyKey: "phase3-result-analysis",
        status: "validated",
        validatedPayload: "{}",
        generatedAt: new Date("2026-07-31T00:00:00.000Z"),
      },
    });
    const evidence = await prisma.guideVisualEvidence.create({
      data: {
        analysisResultId: analysis.id,
        videoId,
        startSeconds: 10,
        endSeconds: 25,
        evidenceType: "transcript_citation",
        normalizedPayload: "{}",
        exactVisibleText: "",
        confidence: 0.96,
        validationStatus: "valid",
        approvalStatus: "automatic_strict",
        purposeSummary: "validated_official_transcript",
      },
    });
    evidenceId = evidence.id;
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("creates exactly one publication under concurrent execution", async () => {
    const now = new Date("2026-07-31T01:00:00.000Z");
    const snapshot = buildAutomaticRecommendationSnapshot({
      characterId: "raiden-shogun",
      videoId,
      claims: [
        {
          claimId: "weapon",
          kind: "weapon",
          entityId: "the-catch",
          slot: null,
          value: "漁獲",
          condition: "",
          confidence: 0.95,
          evidenceSegmentIds: ["segment"],
          evidenceText: "internal transcript text",
          startSeconds: 10,
          endSeconds: 25,
        },
      ],
      overallConfidence: 0.96,
      publishedContentUpdatedAt: now,
    });
    const publish = (leaseOwner: string) =>
      publishAutomaticRecommendation({
        pipelineRunId,
        pipelineItemId: itemId,
        publicationKey,
        analysisIdempotencyKey: analysisKey,
        evidenceId,
        snapshot,
        quality,
        flags,
        dryRun: false,
        now,
        leaseOwner,
      });
    const results = await Promise.all([publish("worker-a"), publish("worker-b")]);
    expect(
      results.filter((result) => result.published && !result.idempotent),
    ).toHaveLength(1);
    await expect(
      prisma.characterBuildRecommendation.count({
        where: { publicationKey },
      }),
    ).resolves.toBe(1);
    await expect(
      prisma.guideRecommendationRevision.count({
        where: { publicationKey },
      }),
    ).resolves.toBe(1);
    await expect(
      prisma.guideAdminAuditLog.count({
        where: { pipelineRunId, action: "automatic_publish" },
      }),
    ).resolves.toBe(1);

    const publicDto = await getPublishedBuildRecommendation("raiden-shogun");
    expect(publicDto).not.toBeNull();
    expect(JSON.stringify(publicDto)).not.toContain("internal transcript text");
    expect(publicDto?.sources).toHaveLength(1);
  });

  it("keeps the published snapshot untouched when a later gate fails", async () => {
    const before = await prisma.characterBuildRecommendation.findUniqueOrThrow({
      where: { publicationKey },
    });
    const result = await publishAutomaticRecommendation({
      pipelineRunId,
      pipelineItemId: itemId,
      publicationKey: "phase3-blocked-publication",
      analysisIdempotencyKey: "phase3-blocked-analysis",
      evidenceId,
      snapshot: buildAutomaticRecommendationSnapshot({
        characterId: "raiden-shogun",
        videoId,
        claims: [
          {
            claimId: "weapon",
            kind: "weapon",
            entityId: "the-catch",
            slot: null,
            value: "漁獲",
            condition: "",
            confidence: 0.95,
            evidenceSegmentIds: ["segment"],
            evidenceText: "never public",
            startSeconds: 10,
            endSeconds: 25,
          },
        ],
        overallConfidence: 0.96,
        publishedContentUpdatedAt: new Date(),
      }),
      quality: { ...quality, transcriptAvailable: false },
      flags,
      dryRun: false,
      now: new Date(),
      leaseOwner: "worker-c",
    });
    expect(result).toMatchObject({ published: false, status: "BLOCKED" });
    const after = await prisma.characterBuildRecommendation.findUniqueOrThrow({
      where: { publicationKey },
    });
    expect(after.id).toBe(before.id);
    expect(after.structuredPayload).toBe(before.structuredPayload);
    expect(after.publishedAt?.toISOString()).toBe(
      before.publishedAt?.toISOString(),
    );
  });
});

async function cleanup(): Promise<void> {
  await prisma.guidePipelineLease.deleteMany({
    where: { lockKey: { startsWith: "youtube-publication:phase3-" } },
  });
  await prisma.guideAdminAuditLog.deleteMany({
    where: { pipelineRunId },
  });
  await prisma.characterBuildRecommendation.deleteMany({
    where: {
      OR: [
        { publicationKey },
        { publicationKey: "phase3-blocked-publication" },
      ],
    },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: { pipelineRunId },
  });
  await prisma.guideVisualAnalysisResult.deleteMany({
    where: { videoId },
  });
  await prisma.guideVideo.deleteMany({ where: { videoId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
