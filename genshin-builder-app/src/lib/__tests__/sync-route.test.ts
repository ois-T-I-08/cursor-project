import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const runSyncExclusive = vi.hoisted(() => vi.fn());
vi.mock("@/lib/sync-execution", async (importOriginal) => {
  const original =
    await importOriginal<typeof import("@/lib/sync-execution")>();
  return { ...original, runSyncExclusive };
});

import { POST } from "@/app/api/sync/route";
import { resetSyncRateLimitForTest } from "@/lib/sync-rate-limit";

const successResult = {
  provider: "test",
  characters: 1,
  weapons: 1,
  materials: 1,
  characterUpgrades: 1,
  weaponUpgrades: 1,
  levelExpSegments: 32,
  expMaterials: 6,
  upgradeApiCalls: 0,
  skippedCharacterUpgrades: 0,
  skippedWeaponUpgrades: 0,
  errors: [] as string[],
};

describe("POST /api/sync", () => {
  beforeEach(() => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("SYNC_API_SECRET", "expected-secret");
    resetSyncRateLimitForTest();
    runSyncExclusive.mockReset();
    runSyncExclusive.mockResolvedValue(successResult);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it.each([
    null,
    "",
    "Bearer ",
    "bearer expected-secret",
    "Basic expected-secret",
    "Bearer expected secret",
    "Bearer expected-secret, Bearer expected-secret",
  ])("returns 401 for missing or malformed authorization: %s", async (value) => {
    const response = await POST(request({ authorization: value }));
    expect(response.status).toBe(401);
    expect(runSyncExclusive).not.toHaveBeenCalled();
  });

  it.each([
    "Bearer wrong",
    "Bearer expired-token",
    "Bearer another-user-token",
    "Bearer tampered-token",
  ])("returns 403 for a well-formed invalid token", async (authorization) => {
    const response = await POST(request({ authorization }));
    expect(response.status).toBe(403);
    expect(runSyncExclusive).not.toHaveBeenCalled();
  });

  it("fails closed in production when secret is unset", async () => {
    vi.stubEnv("SYNC_API_SECRET", "");
    const response = await POST(
      request({ authorization: "Bearer anything" }),
    );
    expect(response.status).toBe(401);
    expect(runSyncExclusive).not.toHaveBeenCalled();
  });

  it.each([
    "{",
    "[]",
    '"string"',
    '{"fullUpgrade":"yes"}',
    '{"userId":"other-user"}',
  ])("rejects an invalid request body without syncing", async (body) => {
    const response = await POST(request({ body }));
    expect(response.status).toBe(400);
    expect(runSyncExclusive).not.toHaveBeenCalled();
  });

  it("rejects declared and streamed oversized bodies", async () => {
    let response = await POST(
      request({
        body: "{}",
        extraHeaders: { "content-length": "5000" },
      }),
    );
    expect(response.status).toBe(413);

    resetSyncRateLimitForTest();
    response = await POST(request({ body: "x".repeat(5000) }));
    expect(response.status).toBe(413);
    expect(runSyncExclusive).not.toHaveBeenCalled();
  });

  it("accepts a valid body and does not expose internal errors", async () => {
    runSyncExclusive.mockResolvedValueOnce({
      ...successResult,
      errors: ["database:private SQL and path"],
    });
    const response = await POST(
      request({ body: '{"fullUpgrade":true}' }),
    );
    const body = await response.json();

    expect(response.status).toBe(502);
    expect(runSyncExclusive).toHaveBeenCalledWith(true);
    expect(body.ok).toBe(false);
    expect(body.errorCount).toBe(1);
    expect(body.errors).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain("private SQL");
  });

  it("returns generic 500 and releases details on internal failure", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    runSyncExclusive.mockRejectedValueOnce(
      new Error("DATABASE_URL=/private/path token=secret"),
    );
    const response = await POST(request({ body: "{}" }));
    const body = await response.json();

    expect(response.status).toBe(500);
    expect(JSON.stringify(body)).not.toContain("private");
    expect(JSON.stringify(body)).not.toContain("secret");
    expect(JSON.stringify(log.mock.calls)).not.toContain("private");
    expect(JSON.stringify(log.mock.calls)).not.toContain("secret");
  });

  it("rate limits repeated authorized requests", async () => {
    for (let index = 0; index < 5; index++) {
      expect((await POST(request({ body: "{}" }))).status).toBe(200);
    }
    expect((await POST(request({ body: "{}" }))).status).toBe(429);
    expect(runSyncExclusive).toHaveBeenCalledTimes(5);
  });
});

function request({
  authorization = "Bearer expected-secret",
  body,
  extraHeaders,
}: {
  authorization?: string | null;
  body?: string;
  extraHeaders?: Record<string, string>;
}): Request {
  const headers = new Headers(extraHeaders);
  if (authorization !== null) {
    headers.set("authorization", authorization);
  }
  if (body !== undefined) headers.set("content-type", "application/json");
  return new Request("https://example.test/api/sync", {
    method: "POST",
    headers,
    body,
  });
}
