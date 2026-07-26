import { afterEach, describe, expect, it, vi } from "vitest";

import {
  fetchJsonObject,
  UpstreamFetchError,
} from "@/lib/api/safe-json-fetch";

describe("fetchJsonObject", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it.each([
    "",
    "<html>failure</html>",
    "{",
    "[]",
    '"string"',
  ])("rejects malformed payload without returning its body", async (body) => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(body, { status: 200 })),
    );

    await expect(fetchSafe()).rejects.toBeInstanceOf(UpstreamFetchError);
  });

  it("accepts unknown fields in an object", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response('{"known":1,"unknown":{"nested":true}}', {
            status: 200,
          }),
      ),
    );

    await expect(fetchSafe()).resolves.toEqual({
      known: 1,
      unknown: { nested: true },
    });
  });

  it.each([500, 502, 503, 504])(
    "rejects status %i without parsing its body",
    async (status) => {
      vi.stubGlobal(
        "fetch",
        vi.fn(
          async () =>
            new Response("<html>private upstream body</html>", { status }),
        ),
      );

      await expect(fetchSafe()).rejects.toMatchObject({
        code: "httpStatus",
        status,
      });
    },
  );

  it("retries a safe GET once and respects Retry-After", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response("", {
          status: 503,
          headers: { "retry-after": "0" },
        }),
      )
      .mockResolvedValueOnce(
        new Response('{"ok":true}', { status: 200 }),
      );
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchSafe({ retries: 1 })).resolves.toEqual({ ok: true });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("times out while waiting for response headers", async () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(() => {})));

    await expect(
      fetchSafe({ timeoutMs: 10 }),
    ).rejects.toMatchObject({ code: "timeout" });
  });

  it("times out while receiving a partial response body", async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"partial":'));
      },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(stream, { status: 200 })),
    );

    await expect(
      fetchSafe({ timeoutMs: 10 }),
    ).rejects.toMatchObject({ code: "timeout" });
  });

  it("rejects declared and streamed oversized bodies", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response("{}", {
            status: 200,
            headers: { "content-length": "100" },
          }),
      ),
    );
    await expect(fetchSafe({ maxBytes: 16 })).rejects.toMatchObject({
      code: "bodyTooLarge",
    });

    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(10));
        controller.enqueue(new Uint8Array(10));
        controller.close();
      },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(stream, { status: 200 })),
    );
    await expect(fetchSafe({ maxBytes: 16 })).rejects.toMatchObject({
      code: "bodyTooLarge",
    });
  });

  it("requires an explicit JSON content type when requested", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response('{"ok":true}', {
            status: 200,
            headers: { "content-type": "text/plain" },
          }),
      ),
    );

    await expect(
      fetchJsonObject("https://example.test/data", {
        timeoutMs: 1_000,
        maxBytes: 1_024,
        retries: 0,
        requireJsonContentType: true,
      }),
    ).rejects.toMatchObject({ code: "invalidData" });
  });

  it("disables automatic redirect following", async () => {
    const fetchMock = vi.fn(async () => {
      throw new TypeError("unexpected redirect");
    });
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchSafe()).rejects.toMatchObject({ code: "network" });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://example.test/data",
      expect.objectContaining({ redirect: "error" }),
    );
  });

  it("rejects HTTP 429 without leaking status body text", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response("rate limited secret-token=abc", {
            status: 429,
            headers: { "retry-after": "1" },
          }),
      ),
    );

    const rejection = fetchSafe();
    await expect(rejection).rejects.toMatchObject({
      code: "httpStatus",
      status: 429,
    });
    await expect(rejection).rejects.toSatisfy((error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      return (
        !message.includes("secret-token") &&
        !message.includes("https://example.test")
      );
    });
  });

  it("aborts in-flight fetch via AbortSignal on timeout", async () => {
    let observedSignal: AbortSignal | undefined;
    vi.stubGlobal(
      "fetch",
      vi.fn(((_url: string, init?: RequestInit) => {
        observedSignal = init?.signal ?? undefined;
        return new Promise<Response>(() => {});
      }) as typeof fetch),
    );

    await expect(fetchSafe({ timeoutMs: 15 })).rejects.toMatchObject({
      code: "timeout",
    });
    expect(observedSignal?.aborted).toBe(true);
  });
});

function fetchSafe(
  overrides: Partial<{
    timeoutMs: number;
    maxBytes: number;
    retries: number;
  }> = {},
) {
  return fetchJsonObject("https://example.test/data", {
    timeoutMs: overrides.timeoutMs ?? 1_000,
    maxBytes: overrides.maxBytes ?? 1_024,
    retries: overrides.retries ?? 0,
  });
}
