import { describe, expect, it, vi } from "vitest";
import { z } from "zod";

import {
  ConsumerApiError,
  requestConsumerApi,
  resolveConsumerApiUrl,
} from "@/lib/consumer-api/client";

const schema = z.strictObject({ ok: z.literal(true), value: z.string() });

function response(
  body: string,
  status = 200,
  contentType = "application/json; charset=utf-8",
) {
  return new Response(body, {
    status,
    headers: { "Content-Type": contentType, "X-Request-Id": "request-123" },
  });
}

function fetchReturning(value: Response): typeof fetch {
  return vi.fn(async () => value) as unknown as typeof fetch;
}

async function expectCode(promise: Promise<unknown>, code: string, status: number | null) {
  await expect(promise).rejects.toMatchObject({ code, status });
}

describe("consumer API client", () => {
  it("parses a valid 200 response and preserves its request ID", async () => {
    const result = await requestConsumerApi({
      baseUrl: "https://example.com",
      path: "/api/consumer/today",
      schema,
      fetchImpl: fetchReturning(response('{"ok":true,"value":"safe"}')),
    });
    expect(result).toEqual({ data: { ok: true, value: "safe" }, requestId: "request-123" });
  });

  it.each([
    [401, "unauthenticated"],
    [403, "forbidden"],
    [404, "notFound"],
    [409, "conflict"],
    [429, "rateLimited"],
    [500, "serviceUnavailable"],
  ] as const)("maps HTTP %i to %s", async (status, code) => {
    await expectCode(
      requestConsumerApi({
        baseUrl: "https://example.com",
        path: "/api/consumer/today",
        schema,
        fetchImpl: fetchReturning(response("{}", status)),
      }),
      code,
      status,
    );
  });

  it("times out and aborts the request", async () => {
    const fetchImpl = vi.fn((_: URL | RequestInfo, init?: RequestInit) =>
      new Promise<Response>((_, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      }),
    ) as unknown as typeof fetch;
    await expectCode(
      requestConsumerApi({
        baseUrl: "https://example.com",
        path: "/api/consumer/today",
        schema,
        timeoutMs: 5,
        fetchImpl,
      }),
      "timeout",
      null,
    );
  });

  it("rejects a non-JSON Content-Type", async () => {
    await expectCode(
      requestConsumerApi({
        baseUrl: "https://example.com",
        path: "/api/consumer/today",
        schema,
        fetchImpl: fetchReturning(response("ok", 200, "text/plain")),
      }),
      "invalidContentType",
      200,
    );
  });

  it("rejects malformed JSON", async () => {
    await expectCode(
      requestConsumerApi({
        baseUrl: "https://example.com",
        path: "/api/consumer/today",
        schema,
        fetchImpl: fetchReturning(response("{")),
      }),
      "malformedResponse",
      200,
    );
  });

  it("rejects a Zod contract failure", async () => {
    await expectCode(
      requestConsumerApi({
        baseUrl: "https://example.com",
        path: "/api/consumer/today",
        schema,
        fetchImpl: fetchReturning(response('{"ok":true,"value":7}')),
      }),
      "contractMismatch",
      200,
    );
  });

  it("allows HTTPS and local HTTP while rejecting unsafe base URLs", () => {
    expect(resolveConsumerApiUrl("https://example.com", "/api/consumer/today").href).toBe(
      "https://example.com/api/consumer/today",
    );
    expect(resolveConsumerApiUrl("http://localhost:3000", "/api/consumer/today").href).toBe(
      "http://localhost:3000/api/consumer/today",
    );
    expect(() => resolveConsumerApiUrl("http://example.com", "/api/consumer/today")).toThrow(
      ConsumerApiError,
    );
    expect(() => resolveConsumerApiUrl("https://token@example.com", "/api/consumer/today")).toThrow(
      ConsumerApiError,
    );
  });
});
