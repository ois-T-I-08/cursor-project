import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("admin build-guides route hardening", () => {
  const env = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    process.env = { ...env };
    vi.restoreAllMocks();
  });

  it("fails closed without secret and rejects missing/wrong bearer", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "");
    const { GET } = await import("../../app/api/admin/build-guides/route");

    const unavailable = await GET(
      new Request("http://localhost/api/admin/build-guides"),
    );
    expect(unavailable.status).toBe(503);

    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "guide-secret-for-route-test");
    vi.resetModules();
    const mod = await import("../../app/api/admin/build-guides/route");

    expect(
      (
        await mod.GET(new Request("http://localhost/api/admin/build-guides"))
      ).status,
    ).toBe(401);
    expect(
      (
        await mod.GET(
          new Request("http://localhost/api/admin/build-guides", {
            headers: { Authorization: "Bearer wrong" },
          }),
        )
      ).status,
    ).toBe(403);
  });

  it("rejects oversized POST bodies", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "guide-secret-for-route-test");
    const { POST } = await import("../../app/api/admin/build-guides/route");
    const huge = await POST(
      new Request("http://localhost/api/admin/build-guides", {
        method: "POST",
        headers: {
          Authorization: "Bearer guide-secret-for-route-test",
          "content-length": "3000000",
          "x-forwarded-for": "203.0.113.11",
        },
        body: "{}",
      }),
    );
    expect(huge.status).toBe(413);
  });

  it.each([
    {
      action: "approveRecommendation",
      recommendationId: "recommendation-1234567890",
    },
    {
      action: "rejectRecommendation",
      recommendationId: "recommendation-1234567890",
    },
    {
      action: "publishRecommendation",
      recommendationId: "recommendation-1234567890",
    },
    {
      action: "unpublishRecommendation",
      recommendationId: "recommendation-1234567890",
    },
    {
      action: "overrideRecommendation",
      recommendationId: "recommendation-1234567890",
      targetsPayload: [],
    },
    {
      action: "restoreRecommendationRevision",
      recommendationId: "recommendation-1234567890",
      revisionId: "revision-123456789012345",
    },
  ])("rejects $action without expectedUpdatedAt", async (payload) => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "guide-secret-for-route-test");
    const { POST } = await import("../../app/api/admin/build-guides/route");
    const response = await POST(
      new Request("http://localhost/api/admin/build-guides", {
        method: "POST",
        headers: {
          Authorization: "Bearer guide-secret-for-route-test",
          "content-type": "application/json",
          "x-forwarded-for": "203.0.113.12",
        },
        body: JSON.stringify(payload),
      }),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({ error: "invalidRequest" });
  });
});
