/**
 * Live dry-run for native-v1 adapter.
 * Does not enable kill switches, does not write DB, does not log URLs or bodies.
 *
 * Usage:
 *   node --env-file=.env --import tsx scripts/yshelper-native-dry-run.mts
 *   node --env-file=.env --import tsx scripts/yshelper-native-dry-run.mts --require-db
 */
import { PrismaClient } from "@prisma/client";

import { NativeV1YshelperAdapter } from "../src/lib/yshelper/adapter";
import {
  hostKindFromDatabaseUrl,
  loadKnownCharacterIds,
  missingCharacterIds,
  parseRequireDb,
} from "../src/lib/yshelper/dry-run-db";
import type { BattleContentType } from "../src/lib/yshelper/types";

const adapter = new NativeV1YshelperAdapter();

type FetchTarget = {
  contentType: BattleContentType;
  label: string;
  pathWithQuery: string;
};

const TARGETS: FetchTarget[] = [
  {
    contentType: "abyss",
    label: "abyss",
    pathWithQuery: "/ys/getAbyssRank.php?star=all&role=all&lang=en",
  },
  {
    contentType: "stygian",
    label: "stygian_nandu6",
    pathWithQuery:
      "/ys/getAbyssRank2.php?star=only_nandu6&role=all&lang=en",
  },
];

const BASE = "https://api.yshelper.com";

async function fetchJson(pathWithQuery: string): Promise<Record<string, unknown>> {
  const url = new URL(pathWithQuery, BASE);
  if (url.origin !== BASE || url.protocol !== "https:") {
    throw new Error("dry_run_origin_rejected");
  }
  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      "User-Agent": "genshin-builder/yshelper-native-dry-run",
    },
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) {
    throw new Error(`dry_run_http_${response.status}`);
  }
  const body: unknown = await response.json();
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new Error("dry_run_invalid_json");
  }
  return body as Record<string, unknown>;
}

function countShortTeams(payload: Record<string, unknown>): number {
  const result = payload.result;
  if (!Array.isArray(result) || !Array.isArray(result[3])) return 0;
  return result[3].filter((team) => {
    if (typeof team !== "object" || team === null) return false;
    const roles = (team as { role?: unknown }).role;
    return Array.isArray(roles) && roles.length > 0 && roles.length < 4;
  }).length;
}

function countTravelerCharacters(payload: Record<string, unknown>): number {
  const result = payload.result;
  if (!Array.isArray(result) || !Array.isArray(result[0])) return 0;
  let count = 0;
  for (const rank of result[0]) {
    if (typeof rank !== "object" || rank === null) continue;
    const list = (rank as { list?: unknown }).list;
    if (!Array.isArray(list)) continue;
    for (const item of list) {
      if (typeof item !== "object" || item === null) continue;
      const ename = (item as { ename?: unknown }).ename;
      if (typeof ename === "string" && ename.trim().toLowerCase() === "traveler") {
        count += 1;
      }
    }
  }
  return count;
}

function countTravelerTeams(payload: Record<string, unknown>): number {
  const result = payload.result;
  if (!Array.isArray(result) || !Array.isArray(result[0]) || !Array.isArray(result[3])) {
    return 0;
  }
  const travelerAvatars = new Set<string>();
  for (const rank of result[0]) {
    if (typeof rank !== "object" || rank === null) continue;
    const list = (rank as { list?: unknown }).list;
    if (!Array.isArray(list)) continue;
    for (const item of list) {
      if (typeof item !== "object" || item === null) continue;
      const row = item as { ename?: unknown; avatar?: unknown };
      if (
        typeof row.ename === "string" &&
        row.ename.trim().toLowerCase() === "traveler" &&
        typeof row.avatar === "string"
      ) {
        travelerAvatars.add(row.avatar);
      }
    }
  }
  let teams = 0;
  for (const team of result[3]) {
    if (typeof team !== "object" || team === null) continue;
    const roles = (team as { role?: unknown }).role;
    if (!Array.isArray(roles) || roles.length !== 4) continue;
    const hit = roles.some((role) => {
      if (typeof role !== "object" || role === null) return false;
      const avatar = (role as { avatar?: unknown }).avatar;
      if (typeof avatar !== "string") return false;
      if (travelerAvatars.has(avatar)) return true;
      return /Player(Girl|Boy)|UI_AvatarIcon_Player/i.test(avatar);
    });
    if (hit) teams += 1;
  }
  return teams;
}

async function main(): Promise<void> {
  const requireDb = parseRequireDb(process.argv.slice(2), process.env);
  const dbUrlKind = hostKindFromDatabaseUrl(process.env.DATABASE_URL);
  const directUrlKind = hostKindFromDatabaseUrl(process.env.DIRECT_URL);

  console.log(
    JSON.stringify({
      phase: "db_probe",
      requireDb,
      DATABASE_URL_set: Boolean(process.env.DATABASE_URL),
      DIRECT_URL_set: Boolean(process.env.DIRECT_URL),
      DATABASE_URL_kind: dbUrlKind,
      DIRECT_URL_kind: directUrlKind,
      dbWrites: 0,
    }),
  );

  if (requireDb && dbUrlKind === "localhost") {
    console.log(
      JSON.stringify({
        phase: "db_error",
        name: "DryRunDatabaseError",
        code: "localhost_not_allowed",
        message: "require_db_rejects_localhost",
        dbWrites: 0,
      }),
    );
    process.exitCode = 1;
    return;
  }

  const prisma = new PrismaClient();
  const dbLoad = await loadKnownCharacterIds(prisma);
  await prisma.$disconnect().catch(() => undefined);

  if (!dbLoad.ok) {
    console.log(
      JSON.stringify({
        phase: "db_error",
        name: dbLoad.name,
        code: dbLoad.code,
        message: dbLoad.message,
        dbWrites: 0,
      }),
    );
    if (requireDb) {
      process.exitCode = 1;
      return;
    }
  }

  const knownIds = dbLoad.ok ? dbLoad.ids : null;
  const unionPublished = new Set<string>();
  const perTargetMissing: Record<string, string[]> = {};

  for (const target of TARGETS) {
    const raw = await fetchJson(target.pathWithQuery);
    const shortTeams = countShortTeams(raw);
    const travelerChars = countTravelerCharacters(raw);
    const travelerTeams = countTravelerTeams(raw);
    const normalized = adapter.adapt(target.contentType, raw);

    const ratesOk =
      normalized.characters.every(
        (c) => c.usageRate >= 0 && c.usageRate <= 1,
      ) &&
      normalized.teams.every((t) => t.usageRate >= 0 && t.usageRate <= 1);

    const teamKeys = normalized.teams.map(
      (t) => `${t.teamKey}|${t.side ?? ""}|${t.stageKey ?? ""}`,
    );
    const uniqueTeamKeys = new Set(teamKeys);
    const duplicateTeamScopes = teamKeys.length - uniqueTeamKeys.size;

    const publishedIds = normalized.characters.map((c) => c.characterId);
    for (const id of publishedIds) unionPublished.add(id);

    const missing =
      knownIds === null
        ? null
        : missingCharacterIds(publishedIds, knownIds);
    if (missing) {
      perTargetMissing[target.label] = missing;
    }

    console.log(
      JSON.stringify({
        label: target.label,
        characters: normalized.characters.length,
        teamsFour: normalized.teams.length,
        shortTeamsExcludedEstimate: shortTeams,
        travelerCharactersSeen: travelerChars,
        travelerTeamsExcludedEstimate: travelerTeams,
        usageRatesInUnitInterval: ratesOk,
        duplicateTeamSideScopes: duplicateTeamScopes,
        publishedCharacterIdsMissingFromDb: missing?.length ?? null,
        knownCharacterRows: knownIds?.size ?? null,
        sampleSize: normalized.sampleSize ?? null,
        seasonId: normalized.seasonId,
        dbWrites: 0,
      }),
    );
  }

  if (knownIds) {
    const unionMissing = missingCharacterIds([...unionPublished], knownIds);
    const summary = {
      phase: "db_summary",
      knownCharacterRows: knownIds.size,
      unionPublishedIds: unionPublished.size,
      unionMissingCount: unionMissing.length,
      abyssMissingCount: perTargetMissing.abyss?.length ?? null,
      stygianMissingCount: perTargetMissing.stygian_nandu6?.length ?? null,
      dbWrites: 0,
      ...(unionMissing.length > 0 ? { missingIds: unionMissing } : {}),
    };
    console.log(JSON.stringify(summary));
    if (requireDb && unionMissing.length > 0) {
      process.exitCode = 1;
    }
  } else if (requireDb) {
    process.exitCode = 1;
  }
}

main().catch(async (error: unknown) => {
  const err = error as { name?: string; code?: string; message?: string };
  console.error(
    JSON.stringify({
      ok: false,
      name: err.name ?? "Error",
      code: err.code ?? null,
      message: String(err.message ?? "dry_run_failed")
        .replace(/postgresql:\/\/[^@\s]+@/gi, "postgresql://***@")
        .replace(/https?:\/\/[^\s]+/gi, "[redacted-url]")
        .slice(0, 200),
      dbWrites: 0,
    }),
  );
  process.exitCode = 1;
});
