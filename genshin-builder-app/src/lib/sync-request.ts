export const SYNC_REQUEST_MAX_BYTES = 4 * 1024;

export class SyncRequestError extends Error {
  constructor(
    readonly status: 400 | 413,
    readonly code: "invalidBody" | "bodyTooLarge",
  ) {
    super(`sync_request_${code}`);
    this.name = "SyncRequestError";
  }
}

export interface SyncRequestPayload {
  fullUpgrade: boolean;
}

export async function parseSyncRequest(
  request: Request,
): Promise<SyncRequestPayload> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > SYNC_REQUEST_MAX_BYTES
  ) {
    throw new SyncRequestError(413, "bodyTooLarge");
  }

  const reader = request.body?.getReader();
  if (!reader) return { fullUpgrade: false };

  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > SYNC_REQUEST_MAX_BYTES) {
        await reader.cancel();
        throw new SyncRequestError(413, "bodyTooLarge");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  if (total === 0) return { fullUpgrade: false };
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new SyncRequestError(400, "invalidBody");
  }
  if (!text.trim()) return { fullUpgrade: false };

  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new SyncRequestError(400, "invalidBody");
  }
  if (
    typeof body !== "object" ||
    body === null ||
    Array.isArray(body)
  ) {
    throw new SyncRequestError(400, "invalidBody");
  }

  const record = body as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.some((key) => key !== "fullUpgrade")) {
    throw new SyncRequestError(400, "invalidBody");
  }
  if (
    record.fullUpgrade !== undefined &&
    typeof record.fullUpgrade !== "boolean"
  ) {
    throw new SyncRequestError(400, "invalidBody");
  }
  return { fullUpgrade: record.fullUpgrade ?? false };
}
