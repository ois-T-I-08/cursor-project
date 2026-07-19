import { describe, expect, it, vi } from "vitest";

import { AbyssStatisticsService } from "@/lib/abyss/statistics-service";
import type { AbyssStatistics } from "@/lib/abyss/types";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import type { AbyssStatisticsProvider } from "@/lib/api/abyss/provider";
import type { AbyssStatisticsCacheStore } from "@/lib/abyss/cache-store";

describe("AbyssStatisticsService", () => {
  it("fetches and stores once on an initial cache miss", async () => {
    const provider = mockProvider();
    const cache = memoryCache(null);
    const service = createService(provider, cache);

    const result = await service.load();

    expect(result.metadata.isStale).toBe(false);
    expect(provider.fetchStatistics).toHaveBeenCalledTimes(1);
    expect(cache.write).toHaveBeenCalledTimes(1);
  });

  it("returns a fresh cache hit without calling the provider", async () => {
    const provider = mockProvider();
    const cache = memoryCache(cachedStatistics({ expiresAt: "2026-07-20T06:00:00.000Z" }));
    const service = createService(provider, cache);

    const result = await service.load();

    expect(result.metadata.isStale).toBe(false);
    expect(provider.fetchStatistics).not.toHaveBeenCalled();
    expect(cache.write).not.toHaveBeenCalled();
  });

  it("refreshes an expired cache and stores the new expiry", async () => {
    const provider = mockProvider();
    const cache = memoryCache(cachedStatistics({ expiresAt: "2026-07-19T00:00:00.000Z" }));
    const service = createService(provider, cache);

    const result = await service.load();

    expect(provider.fetchStatistics).toHaveBeenCalledTimes(1);
    expect(cache.write).toHaveBeenCalledTimes(1);
    expect(result.metadata.fetchedAt).toBe("2026-07-19T03:00:00.000Z");
    expect(result.metadata.expiresAt).toBe("2026-07-19T09:00:00.000Z");
    expect(result.metadata.isStale).toBe(false);
  });

  it.each(["timeout", "rateLimited", "networkError", "invalidResponse"] as const)(
    "falls back to the last successful cache after %s",
    async (code) => {
      const provider = mockProvider(new AbyssStatisticsError(code));
      const cache = memoryCache(cachedStatistics({ expiresAt: "2026-07-19T00:00:00.000Z" }));
      const service = createService(provider, cache);

      const result = await service.load();

      expect(result.metadata).toMatchObject({
        isStale: true,
        warningCode: "staleCache",
        upstreamErrorCode: code,
      });
      expect(cache.write).not.toHaveBeenCalled();
    },
  );

  it("returns a stale cache when the feature flag is disabled", async () => {
    const provider = mockProvider();
    const cache = memoryCache(cachedStatistics());
    const service = createService(provider, cache, false);

    await expect(service.load()).resolves.toMatchObject({
      metadata: {
        isStale: true,
        warningCode: "staleCache",
        upstreamErrorCode: "featureDisabled",
      },
    });
    expect(provider.fetchStatistics).not.toHaveBeenCalled();
  });

  it("returns featureDisabled when disabled without a cache", async () => {
    const service = createService(mockProvider(), memoryCache(null), false);

    await expect(service.load()).rejects.toMatchObject({
      code: "featureDisabled",
    });
  });

  it("deduplicates concurrent refreshes", async () => {
    let resolveFetch: (() => void) | undefined;
    const provider = mockProvider();
    vi.mocked(provider.fetchStatistics).mockImplementation(
      () => new Promise((resolve) => {
        resolveFetch = () => resolve(snapshot());
      }),
    );
    const service = createService(provider, memoryCache(null));

    const first = service.load();
    const second = service.load();
    await vi.waitFor(() => expect(resolveFetch).toBeDefined());
    resolveFetch?.();

    await expect(Promise.all([first, second])).resolves.toHaveLength(2);
    expect(provider.fetchStatistics).toHaveBeenCalledTimes(1);
  });

  it("logs only the approved structured fields", async () => {
    const log = vi.fn();
    const service = createService(mockProvider(), memoryCache(null), true, log);

    await service.load();

    const approved = new Set([
      "sourceApiVersion",
      "scheduleId",
      "itemCount",
      "missingField",
      "invalidField",
      "durationMs",
      "cacheState",
      "fallbackUsed",
    ]);
    for (const [, details] of log.mock.calls) {
      expect(Object.keys(details).every((key) => approved.has(key))).toBe(true);
      expect(JSON.stringify(details)).not.toContain("key_id");
      expect(JSON.stringify(details)).not.toContain("AZA_API");
    }
  });
});

function createService(
  provider: AbyssStatisticsProvider,
  cache: AbyssStatisticsCacheStore,
  enabled = true,
  log = vi.fn(),
) {
  return new AbyssStatisticsService(provider, cache, {
    now: () => new Date("2026-07-19T03:00:00.000Z"),
    ttlSeconds: 21_600,
    enabled: () => enabled,
    log,
  });
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

function memoryCache(initial: AbyssStatistics | null): AbyssStatisticsCacheStore & {
  write: ReturnType<typeof vi.fn>;
} {
  let value = initial;
  return {
    read: vi.fn(async () => value),
    write: vi.fn(async (next: AbyssStatistics) => {
      value = next;
    }),
  };
}

function snapshot() {
  return {
    version: {
      scheduleId: 121,
      periodStart: "2026-07-15T20:00:00.000Z",
      periodEnd: "2026-08-15T19:59:59.000Z",
      sourceApiVersion: "5.6",
    },
    metadata: {
      source: "AZA.GG" as const,
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
  const base = snapshot();
  return {
    ...base,
    metadata: {
      ...base.metadata,
      fetchedAt: "2026-07-19T00:00:00.000Z",
      expiresAt: "2026-07-20T06:00:00.000Z",
      isStale: false,
      ...metadata,
    },
  };
}
