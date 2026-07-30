import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createAbyssStatisticsIngestPost } from "@/app/api/abyss/statistics/ingest/route";
import type { AbyssStatistics } from "@/lib/abyss/types";
import { validAzaPayload } from "./fixtures/aza-abyss";

describe("POST /api/abyss/statistics/ingest", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-19T03:00:00.000Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("returns 503 when ingest secret is unset (fail-closed)", async () => {
    const write = vi.fn();
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "unavailable",
      write,
    });

    const response = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        body: JSON.stringify(validAzaPayload()),
      }),
    );

    expect(response.status).toBe(503);
    expect(write).not.toHaveBeenCalled();
  });

  it("returns 401 when Authorization is missing", async () => {
    const write = vi.fn();
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "missing",
      write,
    });

    const response = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        body: JSON.stringify(validAzaPayload()),
      }),
    );

    expect(response.status).toBe(401);
    expect(write).not.toHaveBeenCalled();
  });

  it("returns 403 when Bearer token is wrong", async () => {
    const write = vi.fn();
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "forbidden",
      write,
    });

    const response = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        headers: { Authorization: "Bearer wrong" },
        body: JSON.stringify(validAzaPayload()),
      }),
    );

    expect(response.status).toBe(403);
    expect(write).not.toHaveBeenCalled();
  });

  it("rejects invalid JSON and non-object roots", async () => {
    const write = vi.fn();
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "authorized",
      write,
    });

    const invalidJson = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        body: "{not-json",
      }),
    );
    expect(invalidJson.status).toBe(400);
    await expect(invalidJson.json()).resolves.toEqual({
      ok: false,
      error: { code: "invalidBody" },
    });

    const arrayRoot = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        body: "[]",
      }),
    );
    expect(arrayRoot.status).toBe(400);
    expect(write).not.toHaveBeenCalled();
  });

  it("normalizes AZA JSON, writes cache, and returns metadata only", async () => {
    const written: AbyssStatistics[] = [];
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "authorized",
      write: async (value) => {
        written.push(value);
      },
      ttlSeconds: () => 21_600,
    });

    const response = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        headers: {
          Authorization: "Bearer test-secret",
          "content-type": "application/json",
        },
        body: JSON.stringify(validAzaPayload()),
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      ok: true,
      expiresAt: "2026-07-19T09:00:00.000Z",
      sampleSize: 1_111,
    });
    expect(body).not.toHaveProperty("data");
    expect(written).toHaveLength(1);
    expect(written[0]?.metadata).toMatchObject({
      source: "AZA.GG",
      sampleSize: 1_111,
      fetchedAt: "2026-07-19T03:00:00.000Z",
      expiresAt: "2026-07-19T09:00:00.000Z",
      isStale: false,
    });
    expect(written[0]?.characters.length).toBeGreaterThan(0);
  });

  it("rejects oversized bodies via content-length", async () => {
    const write = vi.fn();
    const POST = createAbyssStatisticsIngestPost({
      authorize: () => "authorized",
      write,
    });

    const response = await POST(
      new Request("http://localhost/api/abyss/statistics/ingest", {
        method: "POST",
        headers: { "content-length": String(3 * 1024 * 1024) },
        body: "{}",
      }),
    );

    expect(response.status).toBe(413);
    expect(write).not.toHaveBeenCalled();
  });
});
