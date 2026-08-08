import { beforeEach, describe, expect, it, vi } from "vitest";
import { ADMIN_WORKING_DRAFT_KEY } from "../build-guides/guide-admin-form";

const { prismaMock, txMock, fetchArtifactSetsMock } = vi.hoisted(() => {
  const tx = {
    characterBuildRecommendation: {
      update: vi.fn(),
      updateMany: vi.fn(),
      findUnique: vi.fn(),
    },
    recommendationVisualContribution: {
      updateMany: vi.fn(),
    },
    guideRecommendationRevision: {
      create: vi.fn(),
    },
    guideAdminAuditLog: {
      create: vi.fn(),
    },
  };
  return {
    txMock: tx,
    prismaMock: {
      characterBuildRecommendation: {
        findUnique: vi.fn(),
      },
      weapon: {
        findMany: vi.fn(),
      },
      $transaction: vi.fn(),
    },
    fetchArtifactSetsMock: vi.fn(),
  };
});

vi.mock("@/lib/db", () => ({ prisma: prismaMock }));
vi.mock("@/lib/api/amber-details", () => ({
  fetchArtifactSets: fetchArtifactSetsMock,
}));
vi.mock("@/lib/ai/global-ai-emergency", () => ({
  evaluateManualPublishGate: vi.fn(async () => ({
    allowed: true,
    overrideUsed: false,
  })),
  assertGlobalAiEmergencyAllowsExternalCall: vi.fn(async () => undefined),
}));

import { setRecommendationStatus } from "../build-guides/store";

const updatedAt = new Date("2026-07-28T03:04:05.678Z");

function recommendation(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: "recommendation-1",
    characterId: "10000002",
    status: "approved",
    origin: "merged",
    adminNotes: "",
    notes: "",
    overallConfidence: 0.9,
    structuredPayload: JSON.stringify({
      schemaVersion: 1,
      structuredReviewStatus: "admin_confirmed",
      pendingMentions: { weapons: [], artifactSets: [] },
      weapons: [],
      artifactRecommendations: [],
    }),
    targetsPayload: "[]",
    mainStatsPayload: "[]",
    priorityPayload: "[]",
    contextPayload: "{}",
    publishedAt: null,
    lastVerifiedAt: null,
    updatedAt,
    contributions: [],
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  prismaMock.$transaction.mockImplementation(
    async (callback: (tx: typeof txMock) => Promise<unknown>) =>
      callback(txMock),
  );
  prismaMock.weapon.findMany.mockResolvedValue([]);
  fetchArtifactSetsMock.mockResolvedValue([]);
  txMock.characterBuildRecommendation.updateMany.mockResolvedValue({
    count: 1,
  });
  txMock.recommendationVisualContribution.updateMany.mockResolvedValue({
    count: 0,
  });
  txMock.guideRecommendationRevision.create.mockResolvedValue({});
  txMock.guideAdminAuditLog.create.mockResolvedValue({});
});

describe("build guide recommendation status transitions", () => {
  it("approves a working draft without replacing the live published snapshot", async () => {
    const publishedAt = new Date("2026-07-20T00:00:00.000Z");
    const existing = recommendation({
      status: "published",
      publishedAt,
      structuredPayload: JSON.stringify({
        schemaVersion: 1,
        structuredReviewStatus: "admin_confirmed",
        publishedContentUpdatedAt: "2026-07-20T00:00:00.000Z",
        weapons: [{ weaponId: "live-weapon" }],
        [ADMIN_WORKING_DRAFT_KEY]: {
          structured: {
            schemaVersion: 1,
            structuredReviewStatus: "review_required",
            weapons: [{ weaponId: "draft-weapon" }],
          },
          targets: [],
          mainStats: [],
          priority: [],
          context: {},
          adminNotes: "draft note",
          savedAt: "2026-07-28T02:00:00.000Z",
        },
      }),
    });
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue(existing);
    txMock.characterBuildRecommendation.findUnique.mockResolvedValue({
      ...existing,
      status: "published",
    });

    await setRecommendationStatus({
      recommendationId: "recommendation-1",
      status: "approved",
      expectedUpdatedAt: updatedAt.toISOString(),
    });

    const update = txMock.characterBuildRecommendation.updateMany.mock
      .calls[0][0] as {
      data: {
        status: string;
        publishedAt: Date | null;
        lastVerifiedAt: Date | null;
        structuredPayload: string;
      };
    };
    const payload = JSON.parse(update.data.structuredPayload) as Record<
      string,
      unknown
    >;
    const working = payload[ADMIN_WORKING_DRAFT_KEY] as {
      structured: { structuredReviewStatus: string };
    };

    expect(update.data.status).toBe("published");
    expect(update.data.publishedAt).toEqual(publishedAt);
    expect(update.data.lastVerifiedAt).toBeNull();
    expect(payload.weapons).toEqual([{ weaponId: "live-weapon" }]);
    expect(working.structured.structuredReviewStatus).toBe("admin_confirmed");
    expect(txMock.guideRecommendationRevision.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: "approve_draft" }),
      }),
    );
  });

  it("rejects even sub-second stale updates", async () => {
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue(
      recommendation(),
    );

    await expect(
      setRecommendationStatus({
        recommendationId: "recommendation-1",
        status: "approved",
        expectedUpdatedAt: new Date(updatedAt.getTime() + 500).toISOString(),
      }),
    ).rejects.toThrow("conflictUpdatedAt");

    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });

  it("rejects publishing adopted evidence that is not approved", async () => {
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue(
      recommendation({
        contributions: [
          {
            decision: "adopted",
            videoId: "video-1",
            video: {
              privacyStatus: "public",
              channel: { permissionStatus: "approved_for_processing" },
            },
            evidence: { approvalStatus: "pending_review" },
          },
        ],
      }),
    );

    await expect(
      setRecommendationStatus({
        recommendationId: "recommendation-1",
        status: "published",
        expectedUpdatedAt: updatedAt.toISOString(),
      }),
    ).rejects.toThrow("evidenceNotApproved");

    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });

  it.each(["pending_review", "rejected"])(
    "does not publish a %s recommendation",
    async (status) => {
      prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue(
        recommendation({ status }),
      );

      await expect(
        setRecommendationStatus({
          recommendationId: "recommendation-1",
          status: "published",
          expectedUpdatedAt: updatedAt.toISOString(),
        }),
      ).rejects.toThrow("notApproved");

      expect(prismaMock.$transaction).not.toHaveBeenCalled();
    },
  );

  it("does not auto-confirm a review-required draft during publication", async () => {
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue(
      recommendation({
        structuredPayload: JSON.stringify({
          schemaVersion: 1,
          structuredReviewStatus: "review_required",
          pendingMentions: { weapons: [], artifactSets: [] },
          weapons: [],
          artifactRecommendations: [],
        }),
      }),
    );

    await expect(
      setRecommendationStatus({
        recommendationId: "recommendation-1",
        status: "published",
        expectedUpdatedAt: updatedAt.toISOString(),
      }),
    ).rejects.toThrow(/構造化レビューが未完了/);

    expect(prismaMock.$transaction).not.toHaveBeenCalled();
  });
});
