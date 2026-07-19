import { describe, expect, it, vi } from "vitest";

import { createAbyssStatisticsGet } from "@/app/api/abyss/statistics/route";
import type { AbyssStatisticsCacheStore } from "@/lib/abyss/cache-store";
import { AbyssStatisticsService } from "@/lib/abyss/statistics-service";
import type {
  AbyssStatistics,
  AbyssStatisticsSnapshot,
} from "@/lib/abyss/types";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import type { AbyssStatisticsProvider } from "@/lib/api/abyss/provider";

describe("abyss statistics staging paths", () => {
  it("A: initial miss fetches once, stores, and returns fresh HTTP 200", async () => {
    const provider = mockProvider();
    const cache = memoryCache(null);
    const response = await request(provider, cache);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.metadata).toMatchObject({
      source: "AZA.GG",
      isStale: false,
      sampleSize: 1_111,
      fetchedAt: "2026-07-19T03:00:00.000Z",
    });
    expect(provider.fetchStatistics).toHaveBeenCalledTimes(1);
    expect(cache.write).toHaveBeenCalledTimes(1);
  });

  it("B: fresh cache returns HTTP 200 without upstream or DB update", async () => {
    const original = cachedStatistics({
      fetchedAt: "2026-07-19T02:00:00.000Z",
      expiresAt: "2026-07-19T08:00:00.000Z",
    });
    const provider = mockProvider();
    const cache = memoryCache(original);
    const response = await request(provider, cache);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.metadata.isStale).toBe(false);
    expect(body.data.metadata.fetchedAt).toBe(original.metadata.fetchedAt);
    expect(provider.fetchStatistics).not.toHaveBeenCalled();
    expect(cache.write).not.toHaveBeenCalled();
  });

  it("C: expired cache survives upstream failure as stale HTTP 200", async () => {
    const original = cachedStatistics({
      fetchedAt: "2026-07-18T00:00:00.000Z",
      expiresAt: "2026-07-19T00:00:00.000Z",
    });
    const provider = mockProvider(new AbyssStatisticsError("timeout"));
    const cache = memoryCache(original);
    const response = await request(provider, cache);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.metadata).toMatchObject({
      isStale: true,
      warningCode: "staleCache",
      upstreamErrorCode: "timeout",
      fetchedAt: original.metadata.fetchedAt,
    });
    expect(provider.fetchStatistics).toHaveBeenCalledTimes(1);
    expect(cache.write).not.toHaveBeenCalled();
  });

  it("D: kill switch returns cached data as stale without upstream", async () => {
    const provider = mockProvider();
    const cache = memoryCache(cachedStatistics());
    const response = await request(provider, cache, false);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data.metadata).toMatchObject({
      isStale: true,
      warningCode: "staleCache",
      upstreamErrorCode: "featureDisabled",
    });
    expect(provider.fetchStatistics).not.toHaveBeenCalled();
    expect(cache.write).not.toHaveBeenCalled();
  });

  it("D: kill switch without cache returns a safe HTTP 503", async () => {
    const provider = mockProvider();
    const cache = memoryCache(null);
    const response = await request(provider, cache, false);
    const body = await response.json();

    expect(response.status).toBe(503);
    expect(body.error.code).toBe("featureDisabled");
    expect(JSON.stringify(body)).not.toContain("AZA_API");
    expect(provider.fetchStatistics).not.toHaveBeenCalled();
    expect(cache.write).not.toHaveBeenCalled();
  });
});

async function request(
  provider: AbyssStatisticsProvider,
  cache: AbyssStatisticsCacheStore,
  enabled = true,
) {
  const service = new AbyssStatisticsService(provider, cache, {
    now: () => new Date("2026-07-19T03:00:00.000Z"),
    ttlSeconds: 21_600,
    enabled: () => enabled,
    log: vi.fn(),
  });
  return createAbyssStatisticsGet(() => service.load())();
}

function mockProvider(error?: AbyssStatisticsError): AbyssStatisticsProvider {
  return {
    name: "mock",
    fetchStatistics: vi.fn(async () => {
      if (error) throw error;
      return snapshot();
    }),
  };
}

function memoryCache(initial: AbyssStatistics | null):
  AbyssStatisticsCacheStore & { write: ReturnType<typeof vi.fn> } {
  let value = initial;
  return {
    read: vi.fn(async () => value),
    write: vi.fn(async (next: AbyssStatistics) => {
      value = next;
    }),
  };
}

function snapshot(): AbyssStatisticsSnapshot {
  return {
    version: {
      scheduleId: 121,
      periodStart: "2026-07-15T20:00:00.000Z",
      periodEnd: "2026-08-15T19:59:59.000Z",
      sourceApiVersion: "5.6",
    },
    metadata: {
      source: "AZA.GG",
      sourceUpdatedAt: "2026-07-19T02:00:00.000Z",
      sampleSize: 1_111,
      referenceSampleSize: 2_000,
      collectionProgress: 0.668,
    },
    characters: [],
    teams: [],
  };
}

function cachedStatistics(
  metadata: Partial<AbyssStatistics["metadata"]> = {},
): AbyssStatistics {
  return {
    ...snapshot(),
    metadata: {
      ...snapshot().metadata,
      fetchedAt: "2026-07-19T00:00:00.000Z",
      expiresAt: "2026-07-19T09:00:00.000Z",
      isStale: false,
      ...metadata,
    },
  };
}
