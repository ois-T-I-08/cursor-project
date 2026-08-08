import { afterEach, describe, expect, it, vi } from "vitest";

import { logSafeFailure } from "@/lib/safe-error-log";

describe("logSafeFailure", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("logs only opaque code and safe extras, never an Error object", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const secretError = new Error(
      'fetch failed Authorization: Bearer secret-token cookie=ltoken_v2=dummy',
    );
    logSafeFailure("build-guide-analysis", "providerFailed", {
      videoId: "abcdefghijk",
    });
    expect(spy).toHaveBeenCalledOnce();
    const args = spy.mock.calls[0] ?? [];
    const serialized = JSON.stringify(args);
    expect(serialized).toContain("providerFailed");
    expect(serialized).toContain("abcdefghijk");
    expect(serialized).not.toContain("Bearer");
    expect(serialized).not.toContain("ltoken");
    expect(serialized).not.toContain(secretError.message);
    expect(args.some((arg) => arg instanceof Error)).toBe(false);
  });
});
