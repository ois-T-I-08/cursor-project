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
