/**
 * Live dry-run for native-v1 adapter.
 * Does not enable kill switches, does not write DB, does not log URLs or bodies.
 *
 * Usage:
 *   npx tsx scripts/yshelper-native-dry-run.mts
 */
import { PrismaClient } from "@prisma/client";

import { NativeV1YshelperAdapter } from "../src/lib/yshelper/adapter";
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
  // Also count PlayerGirl / PlayerBoy style avatars commonly used for Traveler teams.
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

async function loadKnownCharacterIds(): Promise<Set<string> | null> {
  const prisma = new PrismaClient();
  try {
    const rows = await prisma.character.findMany({ select: { id: true } });
    return new Set(rows.map((row) => row.id));
  } catch {
    return null;
  } finally {
    await prisma.$disconnect().catch(() => undefined);
  }
}

async function main(): Promise<void> {
  const knownIds = await loadKnownCharacterIds();

  for (const target of TARGETS) {
    const raw = await fetchJson(target.pathWithQuery);
    const shortTeams = countShortTeams(raw);
    const travelerChars = countTravelerCharacters(raw);
    const travelerTeams = countTravelerTeams(raw);
    const normalized = adapter.adapt(target.contentType, raw);

    const ratesOk = normalized.characters.every(
      (c) => c.usageRate >= 0 && c.usageRate <= 1,
    ) && normalized.teams.every((t) => t.usageRate >= 0 && t.usageRate <= 1);

    const teamKeys = normalized.teams.map(
      (t) => `${t.teamKey}|${t.side ?? ""}|${t.stageKey ?? ""}`,
    );
    const uniqueTeamKeys = new Set(teamKeys);
    const duplicateTeamScopes = teamKeys.length - uniqueTeamKeys.size;

    const unresolvedPublished =
      knownIds === null
        ? null
        : normalized.characters.filter((c) => !knownIds.has(c.characterId))
            .length;

    // Aggregate-only output (no URL, no body).
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
        publishedCharacterIdsMissingFromDb: unresolvedPublished,
        knownCharacterRows: knownIds?.size ?? null,
        sampleSize: normalized.sampleSize ?? null,
        seasonId: normalized.seasonId,
      }),
    );
  }
}

main().catch(async (error: unknown) => {
  const code =
    error instanceof Error ? error.message.slice(0, 80) : "dry_run_failed";
  console.error(JSON.stringify({ ok: false, code }));
  process.exitCode = 1;
});
