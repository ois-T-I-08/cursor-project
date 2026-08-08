import { afterEach, describe, expect, it, vi } from "vitest";

describe("getBuildProvenance", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it("returns build-time embed for local runtime without Vercel metadata", async () => {
    vi.stubEnv("VERCEL", "");
    vi.stubEnv("VERCEL_GIT_COMMIT_SHA", "");
    vi.stubEnv("GIT_COMMIT_SHA", "");
    vi.stubEnv("GENSIN_BUILD_COMMIT_SHA", "embedded-sha-abc");
    vi.stubEnv("GENSIN_BUILD_BUILT_AT", "2026-08-09T00:00:00.000Z");
    vi.stubEnv("NODE_ENV", "development");
    const { getBuildProvenance } = await import("../build-provenance");
    const p = getBuildProvenance();
    expect(p.runtime).toBe("LOCAL");
    expect(p.commitSha).toBe("embedded-sha-abc");
    expect(p.builtAt).toBe("2026-08-09T00:00:00.000Z");
    expect(p.environment).toBe("development");
  });

  it("prefers VERCEL_GIT_COMMIT_SHA and marks RUNTIME=VERCEL", async () => {
    vi.stubEnv("VERCEL", "1");
    vi.stubEnv("VERCEL_ENV", "production");
    vi.stubEnv("VERCEL_GIT_COMMIT_SHA", "vercel-deploy-sha");
    vi.stubEnv("GENSIN_BUILD_COMMIT_SHA", "embedded-sha-abc");
    const { getBuildProvenance } = await import("../build-provenance");
    const p = getBuildProvenance();
    expect(p.runtime).toBe("VERCEL");
    expect(p.commitSha).toBe("vercel-deploy-sha");
    expect(p.environment).toBe("vercel:production");
  });

  it("does not expose arbitrary env dumps", async () => {
    vi.stubEnv("VERCEL", "");
    vi.stubEnv("GENSIN_BUILD_COMMIT_SHA", "embedded-sha-abc");
    vi.stubEnv("GENSIN_BUILD_BUILT_AT", "2026-08-09T00:00:00.000Z");
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "should-not-appear");
    const { getBuildProvenance } = await import("../build-provenance");
    const json = JSON.stringify(getBuildProvenance());
    expect(json).not.toContain("should-not-appear");
    expect(json).not.toMatch(/password|token|cookie/i);
  });
});
