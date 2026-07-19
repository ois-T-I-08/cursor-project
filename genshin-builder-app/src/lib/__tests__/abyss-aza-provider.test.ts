import { describe, expect, it, vi } from "vitest";

import { AzaAbyssStatisticsProvider } from "@/lib/api/abyss/aza-provider";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import {
  UpstreamFetchError,
  type SafeJsonFetchOptions,
} from "@/lib/api/safe-json-fetch";
import { validAzaPayload } from "./fixtures/aza-abyss";

describe("AzaAbyssStatisticsProvider", () => {
  it("calls the confirmed public endpoint with bounded fetch options", async () => {
    const safeFetch = vi.fn(
      async (_url: string, _options: SafeJsonFetchOptions) => {
        void _url;
        void _options;
        return validAzaPayload();
      },
    );
    const provider = new AzaAbyssStatisticsProvider(safeFetch, {
      AZA_API_BASE_URL: "https://c1-api.aza.gg",
      AZA_REQUEST_TIMEOUT_MS: "10000",
    });

    await expect(provider.fetchStatistics()).resolves.toMatchObject({
      metadata: { source: "AZA.GG" },
    });
    expect(safeFetch).toHaveBeenCalledTimes(1);
    const [url, options] = safeFetch.mock.calls[0];
    expect(url).toBe(
      "https://c1-api.aza.gg/kv/read?key_id=genshin_abyss_statistics",
    );
    expect(options).toMatchObject({
      timeoutMs: 10_000,
      maxBytes: 2 * 1024 * 1024,
      retries: 1,
    });
    expect(options.headers).toMatchObject({
      Accept: "application/json",
      "User-Agent": expect.stringContaining("GenshinBuilder-Web"),
    });
    expect(options.headers).not.toHaveProperty("Authorization");
  });

  it("supports the current API without an API key", async () => {
    const provider = new AzaAbyssStatisticsProvider(
      vi.fn(async () => validAzaPayload()),
      { AZA_API_BASE_URL: "https://c1-api.aza.gg", AZA_API_KEY: "" },
    );

    await expect(provider.fetchStatistics()).resolves.toBeDefined();
  });

  it("continues with a warning when an unknown API version matches the schema", async () => {
    const payload = validAzaPayload();
    (payload.meta as Record<string, unknown>).api_ver = "6.0";
    const versionLogger = vi.fn();
    const provider = new AzaAbyssStatisticsProvider(
      vi.fn(async () => payload),
      { AZA_API_BASE_URL: "https://c1-api.aza.gg" },
      versionLogger,
    );

    await expect(provider.fetchStatistics()).resolves.toMatchObject({
      version: { sourceApiVersion: "6.0", scheduleId: 121 },
    });
    expect(versionLogger).toHaveBeenCalledWith(
      "unknown_api_version_schema_compatible",
      {
        sourceApiVersion: "6.0",
        scheduleId: 121,
        itemCount: 3,
      },
    );
  });

  it("rejects an unknown API version only when its schema is invalid", async () => {
    const payload = validAzaPayload();
    (payload.meta as Record<string, unknown>).api_ver = "6.0";
    delete (payload.data as Record<string, unknown>).schedule;
    const versionLogger = vi.fn();
    const provider = new AzaAbyssStatisticsProvider(
      vi.fn(async () => payload),
      { AZA_API_BASE_URL: "https://c1-api.aza.gg" },
      versionLogger,
    );

    await expect(provider.fetchStatistics()).rejects.toMatchObject({
      code: "invalidResponse",
    });
    expect(versionLogger).toHaveBeenCalledWith(
      "unknown_api_version_schema_invalid",
      {
        sourceApiVersion: "6.0",
        itemCount: 3,
        invalidField: "schema",
      },
    );
  });

  it("returns notConfigured for missing or insecure base URLs", async () => {
    for (const baseUrl of [undefined, "", "http://c1-api.aza.gg"]) {
      const provider = new AzaAbyssStatisticsProvider(
        vi.fn(async () => validAzaPayload()),
        { AZA_API_BASE_URL: baseUrl },
      );
      await expect(provider.fetchStatistics()).rejects.toMatchObject({
        code: "notConfigured",
      });
    }
  });

  it.each([
    [new UpstreamFetchError("timeout"), "timeout"],
    [new UpstreamFetchError("httpStatus", 429), "rateLimited"],
    [new UpstreamFetchError("httpStatus", 500), "networkError"],
    [new UpstreamFetchError("invalidJson"), "invalidResponse"],
    [new UpstreamFetchError("invalidData"), "invalidResponse"],
  ])("maps upstream failure to %s", async (failure, expectedCode) => {
    const provider = new AzaAbyssStatisticsProvider(
      vi.fn(async () => {
        throw failure;
      }),
      { AZA_API_BASE_URL: "https://c1-api.aza.gg" },
    );

    await expect(provider.fetchStatistics()).rejects.toMatchObject({
      code: expectedCode,
    });
  });

  it("does not expose an unexpected exception", async () => {
    const provider = new AzaAbyssStatisticsProvider(
      vi.fn(async () => {
        throw new Error("AZA_API_KEY=private-secret");
      }),
      { AZA_API_BASE_URL: "https://c1-api.aza.gg" },
    );

    await expect(provider.fetchStatistics()).rejects.toEqual(
      new AbyssStatisticsError("unknownError"),
    );
  });
});
