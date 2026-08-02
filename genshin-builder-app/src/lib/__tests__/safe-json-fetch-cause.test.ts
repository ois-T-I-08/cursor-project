import { describe, expect, it } from "vitest";
import { sanitizeNetworkCause, UpstreamFetchError } from "@/lib/api/safe-json-fetch";

describe("sanitizeNetworkCause", () => {
  it("keeps only name/code/syscall from the cause chain", () => {
    const root = Object.assign(new Error("secret https://evil.example/x"), {
      name: "TypeError",
      code: "ENOTFOUND",
      syscall: "getaddrinfo",
    });
    const wrapped = new Error("outer");
    wrapped.cause = root;
    const kind = sanitizeNetworkCause(wrapped);
    expect(kind).toContain("Error");
    expect(kind).toContain("TypeError");
    expect(kind).toContain("ENOTFOUND");
    expect(kind).toContain("getaddrinfo");
    expect(kind).not.toMatch(/https?:\/\//);
    expect(kind).not.toContain("evil");
  });

  it("returns unknown for empty input", () => {
    expect(sanitizeNetworkCause(null)).toBe("unknown");
  });

  it("attaches causeKind on network UpstreamFetchError shape", () => {
    const err = new UpstreamFetchError("network", undefined, undefined, "TypeError/ENOTFOUND");
    expect(err.causeKind).toBe("TypeError/ENOTFOUND");
    expect(err.message).toBe("upstream_network");
  });
});
