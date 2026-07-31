import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetAdminRateLimitForTest } from "@/lib/admin/rate-limit";
import { runYoutubeGuidePipeline } from "@/lib/build-guides/automation/pipeline-runner";
import { DeterministicTranscriptProvider } from "@/lib/build-guides/automation/testing-transcript-provider";
import { DeterministicTranscriptAnalysisProvider } from "@/lib/build-guides/automation/transcript-analysis-provider";

describe("YouTube automation internal pipeline API", () => {
  const env = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
    resetAdminRateLimitForTest("build-guides");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
    process.env = { ...env };
    resetAdminRateLimitForTest("build-guides");
  });

  it("returns 503/401/403 for unavailable or invalid authorization", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "");
    let route = await import(
      "../../app/api/admin/youtube/pipeline/run/route"
    );
    expect((await route.POST(request(null))).status).toBe(503);

    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "phase5-secret");
    vi.resetModules();
    route = await import("../../app/api/admin/youtube/pipeline/run/route");
    expect((await route.POST(request(null))).status).toBe(401);
    expect((await route.POST(request("Bearer wrong"))).status).toBe(403);
  });

  it("rejects oversized or invalid input before invoking the runner", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "phase5-secret");
    const { POST } = await import(
      "../../app/api/admin/youtube/pipeline/run/route"
    );
    const oversized = await POST(
      new Request("http://localhost/api/admin/youtube/pipeline/run", {
        method: "POST",
        headers: {
          Authorization: "Bearer phase5-secret",
          "content-type": "application/json; charset=utf-8",
          "content-length": "20000",
          "x-forwarded-for": "203.0.113.51",
        },
        body: "{}",
      }),
    );
    expect(oversized.status).toBe(413);
    const invalid = await POST(
      new Request("http://localhost/api/admin/youtube/pipeline/run", {
        method: "POST",
        headers: {
          Authorization: "Bearer phase5-secret",
          "content-type": "application/json",
          "x-forwarded-for": "203.0.113.52",
        },
        body: JSON.stringify({
          pipelineRunId: "../../unsafe",
          trigger: "schedule",
          dryRun: true,
        }),
      }),
    );
    expect(invalid.status).toBe(400);
  });

  it("requires JSON Content-Type and accepts only the explicit UTF-8 variant", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "phase5-secret");
    const { POST } = await import(
      "../../app/api/admin/youtube/pipeline/run/route"
    );
    const rejected = [
      null,
      "text/plain",
      "application/x-www-form-urlencoded",
      "multipart/form-data; boundary=x",
      "application/json; charset=shift_jis",
    ];
    for (const [index, contentType] of rejected.entries()) {
      const headers = new Headers({
        Authorization: "Bearer phase5-secret",
        "x-forwarded-for": `203.0.113.${60 + index}`,
      });
      if (contentType) headers.set("content-type", contentType);
      const response = await POST(
        new Request("http://localhost/api/admin/youtube/pipeline/run", {
          method: "POST",
          headers,
          body: "{}",
        }),
      );
      expect(response.status).toBe(415);
    }
  });

  it("returns only the safe pipeline summary", async () => {
    vi.stubEnv("BUILD_GUIDE_ADMIN_SECRET", "phase5-secret");
    vi.doMock("@/lib/build-guides/automation/pipeline-entry", () => ({
      runDefaultYoutubeGuidePipeline: async () => ({
        pipelineRunId: "phase5-run",
        skipped: true,
        dryRun: true,
        discovered: 0,
        published: 0,
        ready: 0,
        blocked: 0,
        retryable: 0,
      }),
    }));
    const { POST } = await import(
      "../../app/api/admin/youtube/pipeline/run/route"
    );
    const response = await POST(
      new Request("http://localhost/api/admin/youtube/pipeline/run", {
        method: "POST",
        headers: {
          Authorization: "Bearer phase5-secret",
          "content-type": "application/json",
          "x-forwarded-for": "203.0.113.53",
        },
        body: JSON.stringify({
          pipelineRunId: "phase5-run",
          trigger: "admin",
          dryRun: true,
        }),
      }),
    );
    expect(response.status).toBe(200);
    const serialized = JSON.stringify(await response.json());
    expect(serialized).not.toContain("transcript");
    expect(serialized).not.toContain("providerResponse");
    expect(serialized).not.toContain("prompt");
  });
});

describe("YouTube automation schedule guard", () => {
  it("skips before DB or providers when flags remain false", async () => {
    const discover = vi.fn(async () => {
      throw new Error("mustNotRun");
    });
    const result = await runYoutubeGuidePipeline({
      pipelineRunId: "phase5-disabled",
      trigger: "test",
      dryRun: true,
      flags: {
        enabled: false,
        guideEnabled: false,
        discoveryEnabled: false,
        transcriptEnabled: false,
        analysisEnabled: false,
        geminiAnalysisEnabled: false,
        deepseekAnalysisEnabled: false,
        autoPublishEnabled: false,
        maintenanceEnabled: false,
      },
      discover,
      transcriptProvider: new DeterministicTranscriptProvider(new Map()),
      analysisProvider: new DeterministicTranscriptAnalysisProvider({}),
      loadKnownEntityIds: async () => new Set(),
    });
    expect(result).toMatchObject({ skipped: true, discovered: 0 });
    expect(discover).not.toHaveBeenCalled();
  });
});

function request(authorization: string | null): Request {
  const headers = new Headers({
    "content-type": "application/json",
    "x-forwarded-for": "203.0.113.50",
  });
  if (authorization) headers.set("authorization", authorization);
  return new Request("http://localhost/api/admin/youtube/pipeline/run", {
    method: "POST",
    headers,
    body: JSON.stringify({
      pipelineRunId: "phase5-auth-run",
      trigger: "admin",
      dryRun: true,
    }),
  });
}
