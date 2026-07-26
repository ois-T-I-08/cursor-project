import type {
  CanonicalSourceCharacter,
  CanonicalSourcePayload,
  CanonicalSourceTeam,
} from "./types";

const CHARACTER_ID = /^\d{4,16}$/;
const SAFE_VERSION = /^[A-Za-z0-9._-]{1,64}$/;
const SAFE_SEASON = /^[A-Za-z0-9._:-]{1,128}$/;
const SAFE_SCOPE = /^[A-Za-z0-9._:-]{1,64}$/;
const MAX_TEAMS = 20_000;
const MAX_CHARACTERS = 1_000;

export class YshelperSchemaError extends Error {
  constructor(readonly field: string) {
    super("yshelper_invalid_response");
    this.name = "YshelperSchemaError";
  }
}

/**
 * Repository-local fixture/bridge contract.
 *
 * This is intentionally not presented as the undocumented YShelper response
 * schema. Production may select it only when an operator has verified that a
 * configured endpoint emits this exact canonical-v1 envelope.
 */
export function parseCanonicalPayload(
  input: Record<string, unknown>,
): CanonicalSourcePayload {
  exactKeys(
    input,
    [
      "contractVersion",
      "sourceVersion",
      "seasonId",
      "sourceUpdatedAt",
      "rateUnit",
      "sampleSize",
      "teams",
      "characters",
      "metadata",
    ],
    "$",
  );
  if (input.contractVersion !== "canonical-v1") fail("contractVersion");
  const sourceVersion = string(
    input.sourceVersion,
    SAFE_VERSION,
    "sourceVersion",
  );
  const seasonId = string(input.seasonId, SAFE_SEASON, "seasonId");
  const sourceUpdatedAt = isoDate(input.sourceUpdatedAt, "sourceUpdatedAt");
  const rateUnit = input.rateUnit;
  if (rateUnit !== "ratio" && rateUnit !== "percent") fail("rateUnit");
  const sampleSize = optionalInteger(input.sampleSize, "sampleSize");
  const teams = array(input.teams, MAX_TEAMS, "teams").map((item, index) =>
    parseTeam(object(item, `teams[${index}]`), index),
  );
  const characters = array(
    input.characters,
    MAX_CHARACTERS,
    "characters",
  ).map((item, index) =>
    parseCharacter(object(item, `characters[${index}]`), index),
  );
  const metadata =
    input.metadata === undefined ? {} : object(input.metadata, "metadata");
  return {
    contractVersion: "canonical-v1",
    sourceVersion,
    seasonId,
    sourceUpdatedAt,
    rateUnit,
    sampleSize,
    teams,
    characters,
    metadata,
  };
}

function parseTeam(
  value: Record<string, unknown>,
  index: number,
): CanonicalSourceTeam {
  const base = `teams[${index}]`;
  exactKeys(
    value,
    [
      "characters",
      "usageRate",
      "usageCount",
      "rank",
      "side",
      "stageKey",
      "sampleSize",
      "metadata",
    ],
    base,
  );
  const characters = array(value.characters, 4, `${base}.characters`).map(
    (item, memberIndex) =>
      string(item, CHARACTER_ID, `${base}.characters[${memberIndex}]`),
  );
  if (characters.length !== 4) fail(`${base}.characters`);
  return {
    characters,
    usageRate: finiteNumber(value.usageRate, `${base}.usageRate`),
    usageCount: optionalInteger(value.usageCount, `${base}.usageCount`),
    rank: optionalInteger(value.rank, `${base}.rank`, 1),
    side: optionalString(value.side, SAFE_SCOPE, `${base}.side`),
    stageKey: optionalString(
      value.stageKey,
      SAFE_SCOPE,
      `${base}.stageKey`,
    ),
    sampleSize: optionalInteger(value.sampleSize, `${base}.sampleSize`),
    metadata:
      value.metadata === undefined
        ? {}
        : object(value.metadata, `${base}.metadata`),
  };
}

function parseCharacter(
  value: Record<string, unknown>,
  index: number,
): CanonicalSourceCharacter {
  const base = `characters[${index}]`;
  exactKeys(
    value,
    [
      "characterId",
      "usageRate",
      "usageCount",
      "rank",
      "side",
      "ownershipRate",
      "usageAmongOwnersRate",
      "sampleSize",
    ],
    base,
  );
  return {
    characterId: string(
      value.characterId,
      CHARACTER_ID,
      `${base}.characterId`,
    ),
    usageRate: finiteNumber(value.usageRate, `${base}.usageRate`),
    usageCount: optionalInteger(value.usageCount, `${base}.usageCount`),
    rank: optionalInteger(value.rank, `${base}.rank`, 1),
    side: optionalString(value.side, SAFE_SCOPE, `${base}.side`),
    ownershipRate:
      value.ownershipRate === undefined
        ? undefined
        : finiteNumber(value.ownershipRate, `${base}.ownershipRate`),
    usageAmongOwnersRate:
      value.usageAmongOwnersRate === undefined
        ? undefined
        : finiteNumber(
            value.usageAmongOwnersRate,
            `${base}.usageAmongOwnersRate`,
          ),
    sampleSize: optionalInteger(value.sampleSize, `${base}.sampleSize`),
  };
}

function object(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail(field);
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, max: number, field: string): unknown[] {
  if (!Array.isArray(value) || value.length > max) fail(field);
  return value;
}

function string(value: unknown, pattern: RegExp, field: string): string {
  if (typeof value !== "string" || !pattern.test(value)) fail(field);
  return value;
}

function optionalString(
  value: unknown,
  pattern: RegExp,
  field: string,
): string | undefined {
  return value === undefined ? undefined : string(value, pattern, field);
}

function finiteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) fail(field);
  return value;
}

function optionalInteger(
  value: unknown,
  field: string,
  min = 0,
): number | undefined {
  if (value === undefined) return undefined;
  if (!Number.isSafeInteger(value) || (value as number) < min) fail(field);
  return value as number;
}

function isoDate(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length > 40 ||
    Number.isNaN(Date.parse(value))
  ) {
    fail(field);
  }
  return new Date(value).toISOString();
}

function exactKeys(
  value: Record<string, unknown>,
  allowed: string[],
  field: string,
): void {
  const allowedSet = new Set(allowed);
  if (Object.keys(value).some((key) => !allowedSet.has(key))) {
    fail(`${field}.unknownField`);
  }
}

function fail(field: string): never {
  throw new YshelperSchemaError(field);
}
