import { NextResponse } from "next/server";
import {
  authorizeBearerSecret,
  authorizationHttpStatus,
  type AdminAuthorization,
} from "@/lib/admin/bearer-auth";
import { PrismaAbyssStatisticsCacheStore } from "@/lib/abyss/cache-store";
import type { AbyssStatistics } from "@/lib/abyss/types";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import { normalizeAzaAbyssStatistics } from "@/lib/api/abyss/normalize-aza";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_BODY_BYTES = 2 * 1024 * 1024;
const DEFAULT_TTL_SECONDS = 21_600;

type IngestLogger = (
  event: string,
  details: { itemCount?: number; durationMs?: number; sampleSize?: number },
) => void;

type IngestDeps = {
  authorize: (request: Request) => AdminAuthorization;
  write: (value: AbyssStatistics) => Promise<void>;
  now?: () => Date;
  ttlSeconds?: () => number;
  log?: IngestLogger;
};

export function createAbyssStatisticsIngestPost(deps: IngestDeps) {
  return async function POST(request: Request): Promise<Response> {
    const auth = deps.authorize(request);
    if (auth !== "authorized") {
      return NextResponse.json(
        {
          ok: false,
          error: {
            code: auth === "unavailable" ? "unavailable" : "unauthorized",
          },
        },
        {
          status: authorizationHttpStatus(auth),
          headers: { "Cache-Control": "no-store" },
        },
      );
    }

    const contentLength = Number(request.headers.get("content-length") ?? 0);
    if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
      return NextResponse.json(
        { ok: false, error: { code: "requestTooLarge" } },
        { status: 413, headers: { "Cache-Control": "no-store" } },
      );
    }

    const started = Date.now();
    let text: string;
    try {
      text = await request.text();
    } catch {
      return invalidBody();
    }
    if (Buffer.byteLength(text, "utf8") > MAX_BODY_BYTES) {
      return NextResponse.json(
        { ok: false, error: { code: "requestTooLarge" } },
        { status: 413, headers: { "Cache-Control": "no-store" } },
      );
    }

    let raw: unknown;
    try {
      raw = JSON.parse(text) as unknown;
    } catch {
      return invalidBody();
    }
    if (!isPlainObject(raw)) {
      return invalidBody();
    }

    try {
      const snapshot = normalizeAzaAbyssStatistics(raw);
      const now = (deps.now ?? (() => new Date()))();
      const ttlSeconds = (deps.ttlSeconds ?? readTtlSeconds)();
      const value: AbyssStatistics = {
        ...snapshot,
        metadata: {
          ...snapshot.metadata,
          fetchedAt: now.toISOString(),
          expiresAt: new Date(now.getTime() + ttlSeconds * 1_000).toISOString(),
          isStale: false,
        },
      };
      await deps.write(value);
      const itemCount = value.characters.length + value.teams.length;
      (deps.log ?? defaultLogger)("ingest_success", {
        itemCount,
        sampleSize: value.metadata.sampleSize,
        durationMs: Date.now() - started,
      });
      return NextResponse.json(
        {
          ok: true,
          expiresAt: value.metadata.expiresAt,
          sampleSize: value.metadata.sampleSize,
        },
        { status: 200, headers: { "Cache-Control": "no-store" } },
      );
    } catch (error) {
      const code =
        error instanceof AbyssStatisticsError ? error.code : "invalidResponse";
      (deps.log ?? defaultLogger)("ingest_failed", {
        durationMs: Date.now() - started,
      });
      return NextResponse.json(
        { ok: false, error: { code } },
        {
          status: code === "noData" ? 422 : 400,
          headers: { "Cache-Control": "no-store" },
        },
      );
    }
  };
}

export const POST = createAbyssStatisticsIngestPost({
  authorize: (request) =>
    authorizeBearerSecret(request, "ABYSS_INGEST_SECRET"),
  write: (value) => new PrismaAbyssStatisticsCacheStore().write(value),
});

function invalidBody(): Response {
  return NextResponse.json(
    { ok: false, error: { code: "invalidBody" } },
    { status: 400, headers: { "Cache-Control": "no-store" } },
  );
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readTtlSeconds(): number {
  const value = process.env.AZA_CACHE_TTL_SECONDS?.trim();
  if (!value) return DEFAULT_TTL_SECONDS;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 300 && parsed <= 86_400
    ? parsed
    : DEFAULT_TTL_SECONDS;
}

function defaultLogger(
  event: string,
  details: { itemCount?: number; durationMs?: number; sampleSize?: number },
): void {
  console.info("abyss_statistics_ingest", { event, ...details });
}
