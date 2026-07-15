import { afterEach, describe, expect, it, vi } from "vitest";
import {
  authorizeSyncRequest,
  verifySyncActionSecret,
  verifySyncApiSecret,
} from "@/lib/sync-auth";

describe("sync authentication", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("fails closed when production secret is unset", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("SYNC_API_SECRET", "");

    expect(verifySyncActionSecret(undefined)).toBe(false);
  });

  it("requires an exact action secret", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("SYNC_API_SECRET", "expected-secret");

    expect(verifySyncActionSecret("wrong")).toBe(false);
    expect(verifySyncActionSecret("expected-secret")).toBe(true);
  });

  it("requires a Bearer token for the API route", () => {
    vi.stubEnv("SYNC_API_SECRET", "expected-secret");

    expect(verifySyncApiSecret(new Request("https://example.test"))).toBe(false);
    expect(
      verifySyncApiSecret(
        new Request("https://example.test", {
          headers: { authorization: "Bearer expected-secret" },
        }),
      ),
    ).toBe(true);
  });

  it.each([
    "Bearer expected-secret ",
    "Bearer  expected-secret",
    "Bearer expected-secret, Bearer expected-secret",
  ])("rejects whitespace or duplicate authorization values", (value) => {
    vi.stubEnv("SYNC_API_SECRET", "expected-secret");
    const request = {
      headers: { get: () => value },
    } as unknown as Request;
    expect(authorizeSyncRequest(request)).toBe("missing");
  });
});
