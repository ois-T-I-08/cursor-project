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

  it("allows a fixed query string on the relative endpoint", () => {
    expect(
      resolveEndpoint("abyss", {
        YSHELPER_API_BASE_URL: "https://api.yshelper.com",
        YSHELPER_ABYSS_ENDPOINT:
          "/ys/getAbyssRank.php?star=all&role=all&lang=en",
      }),
    ).toBe(
      "https://api.yshelper.com/ys/getAbyssRank.php?star=all&role=all&lang=en",
    );
    expect(
      resolveEndpoint("stygian", {
        YSHELPER_API_BASE_URL: "https://api.yshelper.com",
        YSHELPER_STYGIAN_ENDPOINT:
          "/ys/getAbyssRank2.php?star=only_nandu6&role=all&lang=en",
      }),
    ).toBe(
      "https://api.yshelper.com/ys/getAbyssRank2.php?star=only_nandu6&role=all&lang=en",
    );
  });

  it("maps upstream HTTP failures without leaking URL or body text", async () => {
    const fetchImpl = vi.fn(async () =>
      new Response("upstream secret body with token=abc", {
        status: 429,
        headers: { "Content-Type": "application/json" },
      }),
    );
    const client = new YshelperHttpClient({
      fetchImpl: fetchImpl as typeof fetch,
      env: {
        YSHELPER_API_BASE_URL: "https://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss?star=all",
        YSHELPER_API_TOKEN: "client-secret-token",
      },
    });

    const rejection = client.fetch("abyss");
    await expect(rejection).rejects.toMatchObject({
      code: "httpStatus",
      status: 429,
    });
    await expect(rejection).rejects.toSatisfy((error: unknown) => {
      const text = error instanceof Error ? error.message : String(error);
      return (
        !text.includes("token=abc") &&
        !text.includes("client-secret-token") &&
        !text.includes("statistics.example.test")
      );
    });
  });

  it("rejects HTTP, absolute endpoints, other origins, and fragments", () => {
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
        YSHELPER_ABYSS_ENDPOINT: "//other.example.test/abyss",
      },
      {
        YSHELPER_API_BASE_URL: "https://statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss#section",
      },
      {
        YSHELPER_API_BASE_URL: "https://user:pass@statistics.example.test",
        YSHELPER_ABYSS_ENDPOINT: "/verified/abyss",
      },
    ];
    for (const env of invalid) {
      expect(() => resolveEndpoint("abyss", env)).toThrow(
        YshelperClientConfigurationError,
      );
    }
  });
});
