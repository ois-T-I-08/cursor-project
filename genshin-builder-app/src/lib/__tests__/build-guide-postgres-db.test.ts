import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { ADMIN_WORKING_DRAFT_KEY } from "@/lib/build-guides/guide-admin-form";
import { buildPublicRecommendationEtag } from "@/lib/build-guides/public-etag";
import {
  getPublishedBuildRecommendation,
  overrideRecommendation,
  setRecommendationStatus,
  unpublishRecommendation,
} from "@/lib/build-guides/store";

const runDbTests = process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const characterId = "bg-db-char-10000002";
const channelId = "UCBUILDGUIDETEST0000001";
const videoId = "bgTestVid01";

describe.runIf(runDbTests)("build guide PostgreSQL integration", () => {
  beforeAll(async () => {
    await clearGuideData();
    await prisma.character.create({
      data: {
        id: characterId,
        name: "Guide DB Test Character",
        element: "anemo",
        weaponType: "sword",
        rarity: 5,
        region: "test",
        iconUrl: "https://example.com/icon.png",
      },
    });
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Test Channel",
        enabled: true,
        permissionStatus: "approved_for_processing",
        dailyAnalysisLimit: 20,
      },
    });
    await prisma.guideVideo.create({
      data: {
        videoId,
        channelId,
        title: "【原神】テスト育成ガイド",
        description: "",
        thumbnailUrl: "https://example.com/thumb.jpg",
        privacyStatus: "public",
        metadataHash: "meta-hash-test",
        sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
        analysisStatus: "analyzed",
      },
    });
  });

  afterAll(async () => {
    await clearGuideData();
    await prisma.character.deleteMany({ where: { id: characterId } });
    await prisma.$disconnect();
  });

  it("keeps published snapshot on draft save, rejects stale lock, publish/unpublish", async () => {
    const created = await prisma.characterBuildRecommendation.create({
      data: {
        characterId,
        status: "approved",
        origin: "merged",
        overallConfidence: 0.8,
        notes: "",
        adminNotes: "secret-admin-note",
        targetsPayload: JSON.stringify([
          {
            stat: "er",
            unit: "percent",
            recommended: 180,
            min: 160,
            max: 200,
          },
        ]),
        mainStatsPayload: "[]",
        priorityPayload: "[]",
        contextPayload: "{}",
        structuredPayload: JSON.stringify({
          schemaVersion: 1,
          structuredReviewStatus: "admin_confirmed",
          pendingMentions: { weapons: [], artifactSets: [] },
          weapons: [],
          artifactRecommendations: [],
        }),
      },
    });

    const published = await setRecommendationStatus({
      recommendationId: created.id,
      status: "published",
      expectedUpdatedAt: created.updatedAt.toISOString(),
    });
    expect(published.status).toBe("published");
    expect(published.publishedAt).not.toBeNull();

    const beforePublic = await getPublishedBuildRecommendation(characterId);
    expect(beforePublic).not.toBeNull();
    const beforeEtag = buildPublicRecommendationEtag(characterId, beforePublic!);
    expect(JSON.stringify(beforePublic)).not.toContain("secret-admin-note");
    expect(JSON.stringify(beforePublic)).not.toContain(ADMIN_WORKING_DRAFT_KEY);

    const draftSaveResult = await overrideRecommendation({
      recommendationId: published.id,
      expectedUpdatedAt: published.updatedAt.toISOString(),
      keepPublished: true,
      adminNotes: "draft-only-note",
      targetsPayload: [
        {
          stat: "er",
          unit: "percent",
          recommended: 999,
          min: 900,
          max: 1000,
        },
      ],
      structuredPayload: {
        schemaVersion: 1,
        structuredReviewStatus: "draft",
        pendingMentions: { weapons: [], artifactSets: [] },
        weapons: [],
        artifactRecommendations: [],
      },
    });
    const draftSave = draftSaveResult.recommendation;
    expect(draftSave.status).toBe("published");

    const afterDraftPublic = await getPublishedBuildRecommendation(characterId);
    expect(afterDraftPublic).not.toBeNull();
    expect(buildPublicRecommendationEtag(characterId, afterDraftPublic!)).toBe(beforeEtag);
    expect(afterDraftPublic?.targets?.[0]?.recommended).toBe(180);
    expect(JSON.stringify(afterDraftPublic)).not.toContain("draft-only-note");
    expect(JSON.stringify(afterDraftPublic)).not.toContain("999");

    await expect(
      overrideRecommendation({
        recommendationId: draftSave.id,
        expectedUpdatedAt: new Date(
          draftSave.updatedAt.getTime() - 60_000,
        ).toISOString(),
        keepPublished: true,
        targetsPayload: [],
      }),
    ).rejects.toThrow("conflictUpdatedAt");

    const unpublished = await unpublishRecommendation(
      draftSave.id,
      draftSave.updatedAt.toISOString(),
    );
    expect(unpublished.status).toBe("approved");
    expect(unpublished.publishedAt).toBeNull();
    expect(await getPublishedBuildRecommendation(characterId)).toBeNull();

    const revisions = await prisma.guideRecommendationRevision.count({
      where: { recommendationId: created.id },
    });
    expect(revisions).toBeGreaterThanOrEqual(2);
  });
});

async function clearGuideData(): Promise<void> {
  await prisma.guideAdminAuditLog.deleteMany({});
  await prisma.guideRecommendationRevision.deleteMany({
    where: { recommendation: { characterId } },
  });
  await prisma.recommendationVisualContribution.deleteMany({
    where: { recommendation: { characterId } },
  });
  await prisma.characterBuildRecommendation.deleteMany({
    where: { characterId },
  });
  await prisma.guideVisualEvidence.deleteMany({ where: { videoId } });
  await prisma.guideVisualAnalysisResult.deleteMany({ where: { videoId } });
  await prisma.guideVisualAnalysisJob.deleteMany({ where: { videoId } });
  await prisma.guideVideo.deleteMany({ where: { videoId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
