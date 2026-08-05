import "server-only";

import type { z } from "zod";

export type ConsumerApiErrorCode =
  | "unauthenticated"
  | "forbidden"
  | "notFound"
  | "conflict"
  | "rateLimited"
  | "serviceUnavailable"
  | "timeout"
  | "cancelled"
  | "invalidContentType"
  | "malformedResponse"
  | "contractMismatch"
  | "networkError";

const ERROR_MESSAGES: Record<ConsumerApiErrorCode, string> = {
  unauthenticated: "ログイン状態を確認できませんでした。",
  forbidden: "この情報を表示する権限がありません。",
  notFound: "対象の情報が見つかりませんでした。",
  conflict: "情報が更新されています。もう一度読み込んでください。",
  rateLimited: "アクセスが集中しています。少し待ってからお試しください。",
  serviceUnavailable: "現在サービスを利用できません。",
  timeout: "読み込みに時間がかかっています。もう一度お試しください。",
  cancelled: "読み込みを中止しました。",
  invalidContentType: "応答形式を確認できませんでした。",
  malformedResponse: "応答を読み取れませんでした。",
  contractMismatch: "受信した情報の形式を確認できませんでした。",
  networkError: "通信できませんでした。接続を確認してください。",
};

export class ConsumerApiError extends Error {
  constructor(
    public readonly code: ConsumerApiErrorCode,
    public readonly status: number | null,
    public readonly requestId: string | null,
  ) {
    super(ERROR_MESSAGES[code]);
    this.name = "ConsumerApiError";
  }
}

export interface ConsumerApiResult<T> {
  data: T;
  requestId: string | null;
}

export interface ConsumerApiRequestOptions<T> {
  baseUrl: string;
  path: `/api/${string}`;
  schema: z.ZodType<T>;
  signal?: AbortSignal;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}

const LOCAL_HTTP_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);
const MAX_RESPONSE_BYTES = 256 * 1024;

function isSafeBaseUrl(url: URL): boolean {
  if (url.username || url.password || url.search || url.hash) return false;
  return url.protocol === "https:" || (url.protocol === "http:" && LOCAL_HTTP_HOSTS.has(url.hostname));
}

export function resolveConsumerApiUrl(baseUrl: string, path: `/api/${string}`): URL {
  const normalized = baseUrl.trim();
  let base: URL;
  try {
    base = new URL(normalized);
  } catch {
    throw new ConsumerApiError("serviceUnavailable", null, null);
  }
  if (!isSafeBaseUrl(base) || !path.startsWith("/api/") || path.includes("\\") || path.startsWith("//")) {
    throw new ConsumerApiError("serviceUnavailable", null, null);
  }
  const resolved = new URL(path, base);
  if (resolved.origin !== base.origin) {
    throw new ConsumerApiError("serviceUnavailable", null, null);
  }
  return resolved;
}

function safeRequestId(value: string | null): string | null {
  return value && /^[A-Za-z0-9_.:-]{1,128}$/.test(value) ? value : null;
}

function statusErrorCode(status: number): ConsumerApiErrorCode | null {
  if (status === 401) return "unauthenticated";
  if (status === 403) return "forbidden";
  if (status === 404) return "notFound";
  if (status === 409) return "conflict";
  if (status === 429) return "rateLimited";
  if (status >= 500) return "serviceUnavailable";
  return status >= 400 ? "serviceUnavailable" : null;
}

function isJsonContentType(contentType: string | null): boolean {
  if (!contentType) return false;
  const mime = contentType.split(";", 1)[0]?.trim().toLowerCase();
  return mime === "application/json" || (mime?.startsWith("application/") === true && mime.endsWith("+json"));
}

export async function requestConsumerApi<T>({
  baseUrl,
  path,
  schema,
  signal,
  timeoutMs = 10_000,
  fetchImpl = fetch,
}: ConsumerApiRequestOptions<T>): Promise<ConsumerApiResult<T>> {
  const url = resolveConsumerApiUrl(baseUrl, path);
  const controller = new AbortController();
  let didTimeout = false;
  const onAbort = () => controller.abort(signal?.reason);
  if (signal?.aborted) onAbort();
  else signal?.addEventListener("abort", onAbort, { once: true });
  const timeout = setTimeout(() => {
    didTimeout = true;
    controller.abort();
  }, Math.max(1, Math.min(timeoutMs, 60_000)));

  try {
    const response = await fetchImpl(url, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "omit",
      redirect: "error",
      signal: controller.signal,
    });
    const requestId = safeRequestId(response.headers.get("x-request-id"));
    const httpError = statusErrorCode(response.status);
    if (httpError) {
      throw new ConsumerApiError(httpError, response.status, requestId);
    }
    if (!isJsonContentType(response.headers.get("content-type"))) {
      throw new ConsumerApiError("invalidContentType", response.status, requestId);
    }

    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
      throw new ConsumerApiError("malformedResponse", response.status, requestId);
    }
    let value: unknown;
    try {
      value = JSON.parse(text) as unknown;
    } catch {
      throw new ConsumerApiError("malformedResponse", response.status, requestId);
    }
    const parsed = schema.safeParse(value);
    if (!parsed.success) {
      throw new ConsumerApiError("contractMismatch", response.status, requestId);
    }
    return { data: parsed.data, requestId };
  } catch (error) {
    if (error instanceof ConsumerApiError) throw error;
    if (didTimeout) throw new ConsumerApiError("timeout", null, null);
    if (signal?.aborted) throw new ConsumerApiError("cancelled", null, null);
    throw new ConsumerApiError("networkError", null, null);
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", onAbort);
  }
}
