import type { BattleContentType } from "./types";

const SAFE_SCOPE = /^[A-Za-z0-9._:-]{1,64}$/;
const SAFE_SEASON = /^[A-Za-z0-9._:-]{1,128}$/;
const CHARACTER_ID = /^\d{4,16}$/;

export class BattleStatsQueryError extends Error {
  constructor() {
    super("invalid_query");
    this.name = "BattleStatsQueryError";
  }
}

export function parseContentType(value: string | null): BattleContentType {
  if (value === "abyss" || value === "stygian") return value;
  throw new BattleStatsQueryError();
}

export function parseInteger(
  value: string | null,
  fallback: number,
  min: number,
  max: number,
): number {
  if (value === null) return fallback;
  if (!/^\d+$/.test(value)) throw new BattleStatsQueryError();
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new BattleStatsQueryError();
  }
  return parsed;
}

export function parseRate(value: string | null): number | undefined {
  if (value === null) return undefined;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1) {
    throw new BattleStatsQueryError();
  }
  return parsed;
}

export function parseOptionalString(
  value: string | null,
  kind: "scope" | "season" | "character",
): string | undefined {
  if (value === null) return undefined;
  const pattern =
    kind === "scope"
      ? SAFE_SCOPE
      : kind === "season"
        ? SAFE_SEASON
        : CHARACTER_ID;
  if (!pattern.test(value)) throw new BattleStatsQueryError();
  return value;
}

export function publicRateLimitResponse(): Response {
  return Response.json(
    {
      ok: false,
      error: {
        code: "rate_limited",
        message: "統計APIへの要求が多すぎます。",
      },
    },
    { status: 429, headers: { "Cache-Control": "no-store" } },
  );
}

export function invalidQueryResponse(): Response {
  return Response.json(
    {
      ok: false,
      error: {
        code: "invalid_query",
        message: "クエリ形式が不正です。",
      },
    },
    { status: 400, headers: { "Cache-Control": "no-store" } },
  );
}
