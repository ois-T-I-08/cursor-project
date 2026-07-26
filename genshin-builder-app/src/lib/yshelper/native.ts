import { YSHELPER_CHARACTER_ID_BY_NAME } from "./character-id-map";
import { normalizeCanonicalPayload } from "./normalize";
import { parseCanonicalPayload, YshelperSchemaError } from "./schema";
import type {
  BattleContentType,
  CanonicalSourceCharacter,
  CanonicalSourcePayload,
  CanonicalSourceTeam,
  NormalizedBattleStats,
} from "./types";

const MAX_CHARACTERS = 1_000;
const MAX_TEAMS = 20_000;
const MAX_TEXT_LENGTH = 2_048;

type JsonObject = Record<string, unknown>;

export function adaptNativeYshelperPayload(
  contentType: BattleContentType,
  input: Record<string, unknown>,
): NormalizedBattleStats {
  const canonical = nativeToCanonical(contentType, input);

  return normalizeCanonicalPayload(
    contentType,
    parseCanonicalPayload(canonical as unknown as Record<string, unknown>),
  );
}

function nativeToCanonical(
  contentType: BattleContentType,
  input: Record<string, unknown>,
): CanonicalSourcePayload {
  if (integer(input.code, "$.code", 0) !== 200) {
    fail("$.code");
  }

  const sampleSize = integerLike(input.top_own, "$.top_own", 1);
  const versionText = text(input.version, "$.version", 128);
  const lastUpdate = text(input.last_update, "$.last_update", 40);
  const sourceVersion = parseSourceVersion(versionText);
  const sourceUpdatedAt = parseSourceUpdatedAt(lastUpdate);
  const seasonId = `${contentType}-${sourceVersion}-${lastUpdate.slice(0, 10)}`;

  const result = array(input.result, 8, "$.result");
  const rankSection = array(result[0], 100, "$.result[0]");
  const teamSection = array(result[3], MAX_TEAMS, "$.result[3]");

  const {
    characters,
    avatarToCharacterId,
    unresolvedNonTravelerCount,
  } = parseCharacters(rankSection, sampleSize);

  // Traveler is intentionally unresolved (element-split IDs). Any other unknown
  // ename must fail closed so map drift cannot silently shrink published stats.
  if (unresolvedNonTravelerCount > 0) {
    fail("$.result[0].unresolvedCharacter");
  }

  const teams = parseTeams(
    teamSection,
    sampleSize,
    avatarToCharacterId,
  );

  if (characters.length === 0) {
    fail("$.result[0]");
  }

  return {
    contractVersion: "canonical-v1",
    sourceVersion,
    seasonId,
    sourceUpdatedAt,
    rateUnit: "percent",
    sampleSize,
    teams,
    characters,
    metadata: {},
  };
}

function parseCharacters(
  rankSection: unknown[],
  sampleSize: number,
): {
  characters: CanonicalSourceCharacter[];
  avatarToCharacterId: ReadonlyMap<string, string>;
  unresolvedNonTravelerCount: number;
} {
  const characters: CanonicalSourceCharacter[] = [];
  const seenIds = new Set<string>();
  const avatarCandidates = new Map<string, string | null>();
  let rank = 0;
  let unresolvedNonTravelerCount = 0;

  for (let rankIndex = 0; rankIndex < rankSection.length; rankIndex += 1) {
    const rankValue = object(
      rankSection[rankIndex],
      `$.result[0][${rankIndex}]`,
    );
    const list = array(
      rankValue.list,
      MAX_CHARACTERS,
      `$.result[0][${rankIndex}].list`,
    );

    for (let itemIndex = 0; itemIndex < list.length; itemIndex += 1) {
      const field = `$.result[0][${rankIndex}].list[${itemIndex}]`;
      const source = object(list[itemIndex], field);
      const sourceName = text(source.ename, `${field}.ename`, 128);
      const characterId = resolveCharacterId(sourceName);
      const avatar = text(source.avatar, `${field}.avatar`, MAX_TEXT_LENGTH);

      if (characterId) {
        const previous = avatarCandidates.get(avatar);
        if (previous === undefined) {
          avatarCandidates.set(avatar, characterId);
        } else if (previous !== characterId) {
          avatarCandidates.set(avatar, null);
        }
      } else if (sourceName.trim().toLowerCase() !== "traveler") {
        unresolvedNonTravelerCount += 1;
      }

      if (!characterId || seenIds.has(characterId)) {
        continue;
      }

      seenIds.add(characterId);
      rank += 1;

      const usageCount = integerLike(source.use, `${field}.use`, 0);
      const usageRate = percentFromCount(
        usageCount,
        sampleSize,
        `${field}.use`,
      );

      characters.push({
        characterId,
        usageRate,
        usageCount,
        rank,
        ownershipRate: percent(
          source.own_rate,
          `${field}.own_rate`,
        ),
        usageAmongOwnersRate: percent(
          source.use_rate,
          `${field}.use_rate`,
        ),
        sampleSize,
      });
    }
  }

  const avatarToCharacterId = new Map<string, string>();
  for (const [avatar, characterId] of avatarCandidates) {
    if (characterId) {
      avatarToCharacterId.set(avatar, characterId);
    }
  }

  return { characters, avatarToCharacterId, unresolvedNonTravelerCount };
}

function parseTeams(
  teamSection: unknown[],
  sampleSize: number,
  avatarToCharacterId: ReadonlyMap<string, string>,
): CanonicalSourceTeam[] {
  const teams: CanonicalSourceTeam[] = [];

  for (let teamIndex = 0; teamIndex < teamSection.length; teamIndex += 1) {
    const field = `$.result[3][${teamIndex}]`;
    const source = object(teamSection[teamIndex], field);
    if (!Array.isArray(source.role) || source.role.length > 8) {
      fail(`${field}.role`);
    }
    const roles = source.role as unknown[];

    // 公開APIとFlutterは4人編成固定。
    // 1～3人編成と、元素を特定できないTraveler編成は公開しない。
    if (roles.length !== 4) {
      continue;
    }

    const characterIds: string[] = [];
    let unresolved = false;

    for (let roleIndex = 0; roleIndex < roles.length; roleIndex += 1) {
      const roleField = `${field}.role[${roleIndex}]`;
      const role = object(roles[roleIndex], roleField);
      const avatar = text(
        role.avatar,
        `${roleField}.avatar`,
        MAX_TEXT_LENGTH,
      );
      const characterId = avatarToCharacterId.get(avatar);

      if (!characterId) {
        unresolved = true;
        break;
      }

      characterIds.push(characterId);
    }

    if (
      unresolved ||
      characterIds.length !== 4 ||
      new Set(characterIds).size !== 4
    ) {
      continue;
    }

    const sourceUsageCount = integerLike(
      source.use,
      `${field}.use`,
      0,
    );

    const sideCounts = [
      {
        side: "upper",
        value: optionalIntegerLike(
          source.up_use_num,
          `${field}.up_use_num`,
        ),
      },
      {
        side: "middle",
        value: optionalIntegerLike(
          source.mid_use_num,
          `${field}.mid_use_num`,
        ),
      },
      {
        side: "lower",
        value: optionalIntegerLike(
          source.down_use_num,
          `${field}.down_use_num`,
        ),
      },
    ] as const;

    const availableSideCounts = sideCounts.filter(
      (
        item,
      ): item is {
        side: "upper" | "middle" | "lower";
        value: number;
      } => item.value !== undefined,
    );

    if (availableSideCounts.length === 0) {
      teams.push({
        characters: characterIds,
        usageRate: percentFromCount(
          sourceUsageCount,
          sampleSize,
          `${field}.use`,
        ),
        usageCount: sourceUsageCount,
        rank: teamIndex + 1,
        sampleSize,
        metadata: {},
      });
      continue;
    }

    const sideTotal = availableSideCounts.reduce(
      (sum, item) => sum + item.value,
      0,
    );

    if (sideTotal !== sourceUsageCount) {
      fail(`${field}.sideUsageCount`);
    }

    for (const item of availableSideCounts) {
      if (item.value === 0) {
        continue;
      }

      teams.push({
        characters: characterIds,
        usageRate: percentFromCount(
          item.value,
          sampleSize,
          `${field}.${item.side}`,
        ),
        usageCount: item.value,
        rank: teamIndex + 1,
        side: item.side,
        sampleSize,
        metadata: {},
      });
    }
  }

  return teams;
}

function resolveCharacterId(name: string): string | undefined {
  return YSHELPER_CHARACTER_ID_BY_NAME[name.trim().toLowerCase()];
}

function parseSourceVersion(value: string): string {
  const version = value.match(/\d+(?:\.\d+)+/)?.[0];
  if (!version) {
    fail("$.version");
  }

  const phase = value.match(/phase\s*([ivx]+)/i)?.[1]?.toLowerCase();
  return phase ? `${version}-phase-${phase}` : version;
}

function parseSourceUpdatedAt(value: string): string {
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}:\d{2}))?$/,
  );
  if (!match) {
    fail("$.last_update");
  }

  const year = match[1];
  const month = match[2];
  const day = match[3];
  const clock = match[4] ?? "00:00";
  const parsed = new Date(`${year}-${month}-${day}T${clock}:00+08:00`);

  if (Number.isNaN(parsed.getTime())) {
    fail("$.last_update");
  }

  // JS Date overflows invalid calendar days (e.g. 2026-02-30 → March).
  // Reject unless the Asia/Shanghai civil date/time matches the input.
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(parsed);
  const read = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((part) => part.type === type)?.value ?? "";
  const roundTripClock = `${read("hour").padStart(2, "0")}:${read("minute").padStart(2, "0")}`;
  if (
    read("year") !== year ||
    read("month") !== month ||
    read("day") !== day ||
    roundTripClock !== clock
  ) {
    fail("$.last_update");
  }

  return parsed.toISOString();
}

function percentFromCount(
  count: number,
  sampleSize: number,
  field: string,
): number {
  const value = (count / sampleSize) * 100;
  if (!Number.isFinite(value) || value < 0 || value > 100) {
    fail(field);
  }
  return value;
}

function percent(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > 100
  ) {
    fail(field);
  }
  return value;
}

function object(value: unknown, field: string): JsonObject {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    fail(field);
  }
  return value as JsonObject;
}

function array(value: unknown, max: number, field: string): unknown[] {
  if (!Array.isArray(value) || value.length > max) {
    fail(field);
  }
  return value;
}

function text(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === "" ||
    value.length > maxLength
  ) {
    fail(field);
  }
  return value;
}

function integer(
  value: unknown,
  field: string,
  min: number,
): number {
  if (!Number.isSafeInteger(value) || (value as number) < min) {
    fail(field);
  }
  return value as number;
}

function integerLike(
  value: unknown,
  field: string,
  min: number,
): number {
  const parsed =
    typeof value === "string" && /^\d+$/.test(value)
      ? Number(value)
      : value;

  return integer(parsed, field, min);
}

function optionalIntegerLike(
  value: unknown,
  field: string,
): number | undefined {
  return value === undefined
    ? undefined
    : integerLike(value, field, 0);
}

function fail(field: string): never {
  throw new YshelperSchemaError(field);
}