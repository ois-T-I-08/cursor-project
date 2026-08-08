import { beforeEach, describe, expect, it, vi } from "vitest";

const {
  prismaMock,
  setVisualEvidenceStatusMock,
  setRecommendationStatusMock,
  evaluateVisualAutoPublishGateMock,
} = vi.hoisted(() => ({
  prismaMock: {
    guideVisualEvidence: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
    },
    characterBuildRecommendation: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
      update: vi.fn(),
    },
    weapon: {
      findMany: vi.fn(),
    },
    guideAdminAuditLog: {
      create: vi.fn(),
    },
  },
  setVisualEvidenceStatusMock: vi.fn(),
  setRecommendationStatusMock: vi.fn(),
  evaluateVisualAutoPublishGateMock: vi.fn(),
}));

vi.mock("@/lib/db", () => ({ prisma: prismaMock }));
vi.mock("@/lib/api/amber-details", () => ({
  fetchArtifactSets: vi.fn().mockResolvedValue([]),
}));
vi.mock("@/lib/build-guides/store", () => ({
  setVisualEvidenceStatus: setVisualEvidenceStatusMock,
  setRecommendationStatus: setRecommendationStatusMock,
}));
vi.mock("@/lib/build-guides/automation/safety-gates", () => ({
  evaluateVisualAutoPublishGate: evaluateVisualAutoPublishGateMock,
  assertEmergencyStopAllowsWork: vi.fn().mockResolvedValue(undefined),
}));

import { isVisualAutoPublishEnabled } from "../build-guides/visual-auto-publish-settings";
import {
  approvePendingVisualRecommendations,
  autoPublishVisualRecommendations,
  publishPendingVisualRecommendations,
} from "../build-guides/visual-auto-publish";

describe("isVisualAutoPublishEnabled", () => {
  it("is fail-closed unless exactly true", () => {
    expect(isVisualAutoPublishEnabled({})).toBe(false);
    expect(isVisualAutoPublishEnabled({ BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "1" })).toBe(
      false,
    );
    expect(
      isVisualAutoPublishEnabled({ BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "TRUE" }),
    ).toBe(false);
    expect(
      isVisualAutoPublishEnabled({ BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true" }),
    ).toBe(true);
  });
});

describe("autoPublishVisualRecommendations", () => {
  const updatedAt = new Date("2026-08-01T00:00:00.000Z");
  const approvedAt = new Date("2026-08-01T00:00:01.000Z");

  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.guideAdminAuditLog.create.mockResolvedValue({});
    prismaMock.weapon.findMany.mockResolvedValue([]);
    prismaMock.characterBuildRecommendation.update.mockResolvedValue({});
    evaluateVisualAutoPublishGateMock.mockResolvedValue({ allowed: true });
  });

  it("skips all work when Safety Switch / autoPublish gate denies", async () => {
    evaluateVisualAutoPublishGateMock.mockResolvedValue({
      allowed: false,
      reason: "EMERGENCY_STOPPED",
    });
    const result = await autoPublishVisualRecommendations({
      evidenceIds: ["ev-1"],
      recommendationIds: ["rec-1"],
    });
    expect(result.recommendationsPublished).toBe(0);
    expect(result.skipped).toEqual([
      { recommendationId: "rec-1", reason: "EMERGENCY_STOPPED" },
    ]);
    expect(setRecommendationStatusMock).not.toHaveBeenCalled();
  });

  it("approves evidence and publishes recommendations when validation allows", async () => {
    prismaMock.guideVisualEvidence.findUnique.mockResolvedValue({
      id: "ev-1",
      validationStatus: "validated",
      approvalStatus: "pending_review",
    });
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue({
      id: "rec-1",
      status: "pending_review",
      updatedAt,
      structuredPayload: "{}",
      contributions: [],
    });
    setRecommendationStatusMock
      .mockResolvedValueOnce({
        id: "rec-1",
        status: "approved",
        updatedAt: approvedAt,
      })
      .mockResolvedValueOnce({
        id: "rec-1",
        status: "published",
        updatedAt: approvedAt,
      });

    const result = await autoPublishVisualRecommendations({
      evidenceIds: ["ev-1"],
      recommendationIds: ["rec-1"],
    });

    expect(setVisualEvidenceStatusMock).toHaveBeenCalledWith({
      evidenceId: "ev-1",
      approvalStatus: "approved",
    });
    expect(setRecommendationStatusMock).toHaveBeenNthCalledWith(1, {
      recommendationId: "rec-1",
      status: "approved",
      expectedUpdatedAt: updatedAt.toISOString(),
    });
    expect(setRecommendationStatusMock).toHaveBeenNthCalledWith(2, {
      recommendationId: "rec-1",
      status: "published",
      expectedUpdatedAt: approvedAt.toISOString(),
    });
    expect(result).toMatchObject({
      evidenceApproved: 1,
      recommendationsApproved: 1,
      recommendationsPublished: 1,
      gearPromotedWeapons: 0,
      gearPromotedArtifacts: 0,
      skipped: [],
    });
  });

  it("leaves recommendation approved when publish is structured-blocked", async () => {
    prismaMock.guideVisualEvidence.findUnique.mockResolvedValue({
      id: "ev-1",
      validationStatus: "validated",
      approvalStatus: "approved",
    });
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue({
      id: "rec-1",
      status: "approved",
      updatedAt,
      structuredPayload: "{}",
      contributions: [],
    });
    setRecommendationStatusMock.mockRejectedValue(
      new Error("structuredPublishBlocked:missingWeapon"),
    );

    const result = await autoPublishVisualRecommendations({
      evidenceIds: ["ev-1"],
      recommendationIds: ["rec-1"],
    });

    expect(setVisualEvidenceStatusMock).not.toHaveBeenCalled();
    expect(setRecommendationStatusMock).toHaveBeenCalledTimes(1);
    expect(result.recommendationsApproved).toBe(1);
    expect(result.recommendationsPublished).toBe(0);
    expect(result.skipped).toEqual([
      { recommendationId: "rec-1", reason: "structuredPublishBlocked" },
    ]);
  });
});

describe("approvePendingVisualRecommendations", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.guideAdminAuditLog.create.mockResolvedValue({});
    prismaMock.weapon.findMany.mockResolvedValue([]);
    prismaMock.characterBuildRecommendation.update.mockResolvedValue({});
    prismaMock.guideVisualEvidence.findMany = vi.fn().mockResolvedValue([]);
    evaluateVisualAutoPublishGateMock.mockResolvedValue({ allowed: true });
  });

  it("approves evidence and recommendations without publishing", async () => {
    const updatedAt = new Date("2026-08-01T00:00:00.000Z");
    prismaMock.characterBuildRecommendation.findMany.mockResolvedValue([
      {
        id: "rec-1",
        status: "pending_review",
        contributions: [{ evidenceId: "ev-1" }],
      },
    ]);
    prismaMock.guideVisualEvidence.findUnique.mockResolvedValue({
      id: "ev-1",
      validationStatus: "validated",
      approvalStatus: "pending_review",
    });
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue({
      id: "rec-1",
      status: "pending_review",
      updatedAt,
      structuredPayload: "{}",
      contributions: [],
    });
    setRecommendationStatusMock.mockResolvedValueOnce({
      id: "rec-1",
      status: "approved",
      updatedAt,
    });

    const result = await approvePendingVisualRecommendations({ limit: 20 });
    expect(result.scanned).toBe(1);
    expect(result.recommendationsApproved).toBe(1);
    expect(result.recommendationsPublished).toBe(0);
    expect(setRecommendationStatusMock).toHaveBeenCalledTimes(1);
    expect(setRecommendationStatusMock).toHaveBeenCalledWith({
      recommendationId: "rec-1",
      status: "approved",
      expectedUpdatedAt: updatedAt.toISOString(),
    });
  });
});

describe("publishPendingVisualRecommendations", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.guideAdminAuditLog.create.mockResolvedValue({});
    prismaMock.weapon.findMany.mockResolvedValue([]);
    prismaMock.characterBuildRecommendation.update.mockResolvedValue({});
    evaluateVisualAutoPublishGateMock.mockResolvedValue({ allowed: true });
  });

  it("scans pending visual recommendations and auto-publishes them", async () => {
    const updatedAt = new Date("2026-08-01T00:00:00.000Z");
    prismaMock.characterBuildRecommendation.findMany.mockResolvedValue([
      {
        id: "rec-1",
        status: "pending_review",
        contributions: [{ evidenceId: "ev-1" }],
      },
    ]);
    prismaMock.guideVisualEvidence.findUnique.mockResolvedValue({
      id: "ev-1",
      validationStatus: "validated",
      approvalStatus: "pending_review",
    });
    prismaMock.characterBuildRecommendation.findUnique.mockResolvedValue({
      id: "rec-1",
      status: "pending_review",
      updatedAt,
      structuredPayload: "{}",
      contributions: [],
    });
    setRecommendationStatusMock
      .mockResolvedValueOnce({
        id: "rec-1",
        status: "approved",
        updatedAt,
      })
      .mockResolvedValueOnce({
        id: "rec-1",
        status: "published",
        updatedAt,
      });

    const result = await publishPendingVisualRecommendations({ limit: 20 });
    expect(result.scanned).toBe(1);
    expect(result.recommendationsPublished).toBe(1);
    expect(prismaMock.characterBuildRecommendation.findMany).toHaveBeenCalled();
  });
});
