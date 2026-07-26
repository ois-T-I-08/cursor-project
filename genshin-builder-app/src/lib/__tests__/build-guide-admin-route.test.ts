import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("admin build-guides route hardening", () => {
  const env = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    process.env = { ...env };
    vi.restoreAllMocks();
  });

  it("fails closed without secret and rejects missing/wrong bearer", async () => {
    delete process.env.BUILD_GUIDE_ADMIN_SECRET;
    const { GET } = await import("../../app/api/admin/build-guides/route");

    const unavailable = await GET(
      new Request("http://localhost/api/admin/build-guides"),
    );
    expect(unavailable.status).toBe(503);
    expect(await unavailable.json()).toEqual({ error: "unavailable" });

    process.env.BUILD_GUIDE_ADMIN_SECRET = "guide-secret-for-route-test";
    vi.resetModules();
    const mod = await import("../../app/api/admin/build-guides/route");

    const missing = await mod.GET(
      new Request("http://localhost/api/admin/build-guides"),
    );
    expect(missing.status).toBe(401);

    const forbidden = await mod.GET(
      new Request("http://localhost/api/admin/build-guides", {
        headers: { Authorization: "Bearer wrong" },
      }),
    );
    expect(forbidden.status).toBe(403);
  });

  it("rejects oversized POST bodies", async () => {
    process.env.BUILD_GUIDE_ADMIN_SECRET = "guide-secret-for-route-test";
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
});
