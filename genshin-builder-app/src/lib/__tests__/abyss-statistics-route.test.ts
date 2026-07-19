import { describe, expect, it } from "vitest";

import { createAbyssStatisticsGet } from "@/app/api/abyss/statistics/route";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import type { AbyssStatistics } from "@/lib/abyss/types";

describe("GET /api/abyss/statistics", () => {
  it("returns normalized data without upstream details", async () => {
    const response = await createAbyssStatisticsGet(async () => data())();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(response.headers.get("x-abyss-data-stale")).toBe("false");
    expect(body).toEqual({ ok: true, data: data() });
    expect(JSON.stringify(body)).not.toContain("key_id");
  });

  it("disables client caching for stale fallback data", async () => {
    const response = await createAbyssStatisticsGet(async () =>
      data({ isStale: true, warningCode: "staleCache" }),
    )();

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-abyss-data-stale")).toBe("true");
  });

  it.each([
    ["timeout", 504],
    ["rateLimited", 503],
    ["networkError", 503],
    ["invalidResponse", 502],
    ["notConfigured", 503],
    ["featureDisabled", 503],
    ["noData", 503],
    ["unknownError", 500],
  ] as const)("maps %s to a safe status", async (code, status) => {
    const response = await createAbyssStatisticsGet(async () => {
      throw new AbyssStatisticsError(code);
    })();
    const body = await response.json();

    expect(response.status).toBe(status);
    expect(body.error.code).toBe(code);
    expect(JSON.stringify(body)).not.toContain("AZA_API");
  });
});

function data(
  metadata: Partial<AbyssStatistics["metadata"]> = {},
): AbyssStatistics {
  return {
    version: {
      scheduleId: 121,
      periodStart: "2026-07-15T20:00:00.000Z",
      periodEnd: "2026-08-15T19:59:59.000Z",
      sourceApiVersion: "5.6",
    },
    metadata: {
      source: "AZA.GG",
      fetchedAt: "2026-07-19T03:00:00.000Z",
      expiresAt: "2026-07-19T09:00:00.000Z",
      sourceUpdatedAt: "2026-07-19T02:00:00.000Z",
      isStale: false,
      sampleSize: 1_111,
      referenceSampleSize: 2_000,
      collectionProgress: 0.668,
      ...metadata,
    },
    characters: [],
    teams: [],
  };
}
