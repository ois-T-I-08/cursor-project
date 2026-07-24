export type UpstreamFailureCode =
  | "timeout"
  | "network"
  | "httpStatus"
  | "bodyTooLarge"
  | "invalidEncoding"
  | "invalidJson"
  | "invalidData";

export class UpstreamFetchError extends Error {
  constructor(
    readonly code: UpstreamFailureCode,
    readonly status?: number,
    readonly retryAfterMs?: number,
  ) {
    super(`upstream_${code}`);
    this.name = "UpstreamFetchError";
  }
}

export interface SafeJsonFetchOptions {
  timeoutMs: number;
  maxBytes: number;
  retries?: number;
  revalidateSeconds?: number;
  requireJsonContentType?: boolean;
  acceptedContentTypes?: readonly string[];
  headers?: HeadersInit;
  fetchImpl?: typeof fetch;
}

export async function fetchJsonObject(
  url: string,
  options: SafeJsonFetchOptions,
): Promise<Record<string, unknown>> {
  const retries = options.retries ?? 2;
  for (let attempt = 0; ; attempt++) {
    try {
      return await fetchJsonObjectOnce(url, options);
    } catch (error) {
      if (!shouldRetry(error) || attempt >= retries) throw error;
      await delay(retryDelayMs(error, attempt));
    }
  }
}

async function fetchJsonObjectOnce(
  url: string,
  options: SafeJsonFetchOptions,
): Promise<Record<string, unknown>> {
  const deadline = Date.now() + options.timeoutMs;
  const controller = new AbortController();
  let response: Response;
  try {
    const fetchImpl = options.fetchImpl ?? fetch;
    response = await withDeadline(
      fetchImpl(url, {
        headers: options.headers,
        next:
          options.revalidateSeconds === undefined
            ? undefined
            : { revalidate: options.revalidateSeconds },
        signal: controller.signal,
      }),
      deadline,
      () => controller.abort(),
    );
  } catch (error) {
    if (error instanceof UpstreamFetchError) throw error;
    if (isAbortError(error)) {
      throw new UpstreamFetchError("timeout");
    }
    throw new UpstreamFetchError("network");
  }

  if (!response.ok) {
    const retryAfterMs = parseRetryAfter(
      response.headers.get("retry-after"),
    );
    await response.body?.cancel().catch(() => undefined);
    throw new UpstreamFetchError(
      "httpStatus",
      response.status,
      retryAfterMs,
    );
  }

  const contentType = response.headers.get("content-type");
  if (
    (options.acceptedContentTypes !== undefined &&
      !isAcceptedContentType(contentType, options.acceptedContentTypes)) ||
    (options.acceptedContentTypes === undefined &&
      options.requireJsonContentType === true &&
      !isJsonContentType(contentType))
  ) {
    await response.body?.cancel().catch(() => undefined);
    throw new UpstreamFetchError("invalidData");
  }

  const declaredLength = Number(response.headers.get("content-length"));
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > options.maxBytes
  ) {
    await response.body?.cancel().catch(() => undefined);
    throw new UpstreamFetchError("bodyTooLarge");
  }

  const bytes = await readBodyWithLimit(
    response,
    options.maxBytes,
    deadline,
  );
  if (bytes.byteLength === 0) {
    throw new UpstreamFetchError("invalidJson");
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new UpstreamFetchError("invalidEncoding");
  }
  if (text.trimStart().startsWith("<")) {
    throw new UpstreamFetchError("invalidJson");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new UpstreamFetchError("invalidJson");
  }
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed)
  ) {
    throw new UpstreamFetchError("invalidData");
  }
  return parsed as Record<string, unknown>;
}

function isJsonContentType(value: string | null): boolean {
  if (!value) return false;
  const mediaType = value.split(";", 1)[0]?.trim().toLowerCase() ?? "";
  return mediaType === "application/json" || mediaType.endsWith("+json");
}

function isAcceptedContentType(
  value: string | null,
  accepted: readonly string[],
): boolean {
  if (!value || accepted.length === 0) return false;
  const mediaType = value.split(";", 1)[0]?.trim().toLowerCase() ?? "";
  return accepted.some(
    (candidate) => candidate.trim().toLowerCase() === mediaType,
  );
}

async function readBodyWithLimit(
  response: Response,
  maxBytes: number,
  deadline: number,
): Promise<Uint8Array> {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();

  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await withDeadline(
        reader.read(),
        deadline,
        () => {
          void reader.cancel();
        },
      );
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        throw new UpstreamFetchError("bodyTooLarge");
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof UpstreamFetchError) throw error;
    if (isAbortError(error)) throw new UpstreamFetchError("timeout");
    throw new UpstreamFetchError("network");
  } finally {
    reader.releaseLock();
  }

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function shouldRetry(error: unknown): boolean {
  if (!(error instanceof UpstreamFetchError)) return false;
  if (error.code === "timeout" || error.code === "network") return true;
  return (
    error.code === "httpStatus" &&
    (error.status === 429 || (error.status !== undefined && error.status >= 500))
  );
}

function retryDelayMs(error: unknown, attempt: number): number {
  if (error instanceof UpstreamFetchError) {
    if (error.retryAfterMs !== undefined) {
      return Math.min(2_000, Math.max(0, error.retryAfterMs));
    }
    if (error.status === 429) {
      return Math.min(2_000, 250 * 2 ** attempt);
    }
  }
  return Math.min(1_000, 100 * 2 ** attempt);
}

function parseRetryAfter(value: string | null): number | undefined {
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return seconds * 1_000;
  const date = Date.parse(value);
  if (Number.isNaN(date)) return undefined;
  return Math.max(0, date - Date.now());
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === "AbortError";
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function withDeadline<T>(
  operation: Promise<T>,
  deadline: number,
  onTimeout: () => void,
): Promise<T> {
  const remaining = deadline - Date.now();
  if (remaining <= 0) {
    onTimeout();
    return Promise.reject(new UpstreamFetchError("timeout"));
  }
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      onTimeout();
      reject(new UpstreamFetchError("timeout"));
    }, remaining);
    operation.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
