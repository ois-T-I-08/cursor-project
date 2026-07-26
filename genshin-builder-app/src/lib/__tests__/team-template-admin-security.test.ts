import { afterEach, describe, expect, it, vi } from "vitest";
import {
  authorizeTemplateAdminRequest,
} from "../team-recommendations/replacements/admin-auth";
import {
  allowTemplateAdminRequest,
  resetTemplateAdminRateLimitForTest,
} from "../team-recommendations/replacements/admin-rate-limit";

afterEach(() => {
  vi.unstubAllEnvs();
  resetTemplateAdminRateLimitForTest();
});

describe("team template admin security", () => {
  it("fails closed when the dedicated secret is not configured", () => {
    vi.stubEnv("TEAM_TEMPLATE_ADMIN_SECRET", "");
    expect(authorizeTemplateAdminRequest(request("Bearer anything"))).toBe(
      "unavailable",
    );
  });

  it("accepts only an exact bearer token", () => {
    vi.stubEnv("TEAM_TEMPLATE_ADMIN_SECRET", "expected-secret");
    expect(authorizeTemplateAdminRequest(request("Bearer expected-secret"))).toBe(
      "authorized",
    );
    expect(authorizeTemplateAdminRequest(request("Bearer wrong-secret"))).toBe(
      "forbidden",
    );
    expect(authorizeTemplateAdminRequest(request("Bearer expected-secret,"))).toBe(
      "missing",
    );
    expect(authorizeTemplateAdminRequest(request(null))).toBe("missing");
  });

  it("limits authorized management calls to ten per minute and resets by window", () => {
    const value = request("Bearer token", "203.0.113.10");
    for (let index = 0; index < 10; index++) {
      expect(allowTemplateAdminRequest(value, 1_000)).toBe(true);
    }
    expect(allowTemplateAdminRequest(value, 1_000)).toBe(false);
    expect(allowTemplateAdminRequest(value, 61_001)).toBe(true);
  });
});

function request(authorization: string | null, forwardedFor?: string): Request {
  const headers = new Headers();
  if (authorization) headers.set("authorization", authorization);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
  return new Request("https://builder.example.com/api/admin/team-templates", {
    headers,
  });
}
