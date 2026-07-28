import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  allowBuildGuideAdminRequest,
  authorizeBuildGuideAdminRequest,
} from "../build-guides/admin-auth";
import { resetAdminRateLimitForTest } from "../admin/rate-limit";

describe("build-guide admin security", () => {
  const env = { ...process.env };

  beforeEach(() => {
    resetAdminRateLimitForTest("build-guides");
    process.env.BUILD_GUIDE_ADMIN_SECRET = "guide-secret";
  });

  afterEach(() => {
    process.env = { ...env };
    resetAdminRateLimitForTest("build-guides");
  });

  it("fails closed with 503 semantics when secret missing", () => {
    delete process.env.BUILD_GUIDE_ADMIN_SECRET;
    expect(authorizeBuildGuideAdminRequest(request("Bearer anything"))).toBe(
      "unavailable",
    );
  });

  it("authorizes only exact bearer token", () => {
    expect(authorizeBuildGuideAdminRequest(request("Bearer guide-secret"))).toBe(
      "authorized",
    );
    expect(authorizeBuildGuideAdminRequest(request("Bearer wrong"))).toBe("forbidden");
    expect(authorizeBuildGuideAdminRequest(request(null))).toBe("missing");
  });

  it("rate limits separately from other scopes", () => {
    const value = request("Bearer guide-secret", "1.2.3.4");
    for (let i = 0; i < 120; i++) {
      expect(allowBuildGuideAdminRequest(value, 1_000)).toBe(true);
    }
    expect(allowBuildGuideAdminRequest(value, 1_000)).toBe(false);
  });
});
function request(authorization: string | null, ip = "9.9.9.9"): Request {
  const headers = new Headers();
  if (authorization) headers.set("authorization", authorization);
  headers.set("x-forwarded-for", ip);
  return new Request("https://builder.example.com/api/admin/build-guides", {
    headers,
  });
}
