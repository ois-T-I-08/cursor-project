import { describe, expect, it, vi } from "vitest";

import {
  resolveEndpoint,
  YshelperClientConfigurationError,
  YshelperHttpClient,
} from "@/lib/yshelper/client";

describe("YshelperHttpClient", () => {
  it("does not call fetch when the explicit endpoint is absent", async () => {
    const fetchImpl = vi.fn();
    const client = new YshelperHttpClient({ fetchImpl, env: {} });

    await expect(client.fetch("abyss")).rejects.toBeInstanceOf(
      YshelperClientConfigurationError,
    );
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("uses only a configured HTTPS origin and explicit relative path", async () => {
    const fetchImpl = vi.fn(async () =>
      new Response('{"contractVersion":"canonical-v1"}', {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    const env = {
      YSHELPER_API_BASE_URL: "https://statistics.example.test",
      YSHELPER_ABYSS_ENDPOINT: "/verified/abyss",
    };
    const client = new YshelperHttpClient({
      fetchImpl: fetchImpl as typeof fetch,
      env,
    });

    await expect(client.fetch("abyss")).resolves.toEqual({
      contractVersion: "canonical-v1",
    });
    expect(resolveEndpoint("abyss", env)).toBe(
      "https://statistics.example.test/verified/abyss",
    );
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it("rejects HTTP, absolute endpoint URLs, query strings, and fragments", () => {
    const invalid = [
      {
        YSHELPER_API_BASE_URL: "http://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss",
      },
      {
        YSHELPER_API_BASE_URL: "https://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "https://other.example.test/abyss",
      },
      {
        YSHELPER_API_BASE_URL: "https://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss?lang=unknown",
      },
      {
        YSHELPER_API_BASE_URL: "https://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss#section",
      },
    ];
    for (const env of invalid) {
      expect(() => resolveEndpoint("abyss", env)).toThrow(
        YshelperClientConfigurationError,
      );
    }
  });
});
