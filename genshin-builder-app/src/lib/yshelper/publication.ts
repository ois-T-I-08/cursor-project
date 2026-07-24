import { createHash } from "node:crypto";

import { prisma } from "@/lib/db";
import type { BattleContentType } from "./types";

export const BATTLE_BUNDLE_PAGE_SIZE = 500;

export interface BattleStatsManifestResponse {
  schemaVersion: 1;
  abyss: BattleStatsManifestItem | null;
  stygian: BattleStatsManifestItem | null;
}

export interface BattleStatsManifestItem {
  seasonId: string;
  revision: number;
  payloadHash: string;
  updatedAt: string;
}

export async function loadBattleStatsManifest(): Promise<{
  data: BattleStatsManifestResponse;
  etag: string;
}> {
  const rows = await prisma.battleStatsManifest.findMany({
    orderBy: { contentType: "asc" },
  });
  const byType = new Map(rows.map((row) => [row.contentType, row]));
  const data: BattleStatsManifestResponse = {
    schemaVersion: 1,
    abyss: manifestItem(byType.get("abyss")),
    stygian: manifestItem(byType.get("stygian")),
  };
  const etag = `"sha256-${createHash("sha256")
    .update(JSON.stringify(data))
    .digest("base64url")}"`;
  return { data, etag };
}

export async function loadBattleStatsBundlePage(input: {
  contentType: BattleContentType;
  revision: number;
  page: number;
}) {
  const manifest = await prisma.battleStatsManifest.findUnique({
    where: { contentType: input.contentType },
    include: { publishedSnapshot: true },
  });
  if (
    !manifest ||
    manifest.revision !== input.revision ||
    manifest.publishedSnapshot.validationState !== "valid" ||
    manifest.publishedSnapshot.publishedAt === null
  ) {
    return null;
  }
  const snapshotId = manifest.publishedSnapshotId;
  const [teamCount, characterCount] = await Promise.all([
    prisma.battleTeamUsage.count({
      where: { snapshotId, isResolved: true },
    }),
    prisma.battleCharacterUsage.count({
      where: { snapshotId, isResolved: true },
    }),
  ]);
  const pageCount = Math.max(
    1,
    Math.ceil(teamCount / BATTLE_BUNDLE_PAGE_SIZE),
    Math.ceil(characterCount / BATTLE_BUNDLE_PAGE_SIZE),
  );
  if (input.page >= pageCount) return null;
  const skip = input.page * BATTLE_BUNDLE_PAGE_SIZE;
  const [teams, characters] = await Promise.all([
    prisma.battleTeamUsage.findMany({
      where: { snapshotId, isResolved: true },
      orderBy: { id: "asc" },
      skip,
      take: BATTLE_BUNDLE_PAGE_SIZE,
      include: { members: { orderBy: { displayOrder: "asc" } } },
    }),
    prisma.battleCharacterUsage.findMany({
      where: { snapshotId, isResolved: true },
      orderBy: { id: "asc" },
      skip,
      take: BATTLE_BUNDLE_PAGE_SIZE,
    }),
  ]);
  const snapshot = manifest.publishedSnapshot;
  return {
    schemaVersion: snapshot.schemaVersion,
    source: "YShelper" as const,
    contentType: input.contentType,
    sourceVersion: snapshot.sourceVersion ?? "unknown",
    seasonId: snapshot.seasonId,
    revision: snapshot.revision,
    payloadHash: snapshot.payloadHash,
    sourceUpdatedAt: snapshot.sourceUpdatedAt.toISOString(),
    sampleSize: snapshot.sampleSize,
    metadata: {},
    page: input.page,
    pageCount,
    teams: teams.map((team) => ({
      teamKey: team.teamKey,
      members: team.members.map((member) => member.characterId),
      usageRate: team.usageRate,
      usageCount: team.usageCount,
      rank: team.rank,
      side: team.side,
      stageKey: team.stageKey,
      sampleSize: team.sampleSize,
    })),
    characters: characters.map((character) => ({
      characterId: character.characterId,
      usageRate: character.usageRate,
      usageCount: character.usageCount,
      rank: character.rank,
      side: character.side,
      ownershipRate: character.ownershipRate,
      usageAmongOwnersRate: character.usageAmongOwnersRate,
      sampleSize: character.sampleSize,
    })),
  };
}

export async function listPublishedTeams(input: {
  contentType: BattleContentType;
  seasonId?: string;
  characterId?: string;
  side?: string;
  stageKey?: string;
  minimumUsageRate?: number;
  limit: number;
  cursor?: string;
}) {
  const manifest = await publishedManifest(input.contentType, input.seasonId);
  if (!manifest) return null;
  const rows = await prisma.battleTeamUsage.findMany({
    where: {
      snapshotId: manifest.publishedSnapshotId,
      isResolved: true,
      id: input.cursor ? { gt: input.cursor } : undefined,
      side: input.side,
      stageKey: input.stageKey,
      usageRate:
        input.minimumUsageRate === undefined
          ? undefined
          : { gte: input.minimumUsageRate },
      members: input.characterId
        ? { some: { characterId: input.characterId } }
        : undefined,
    },
    orderBy: { id: "asc" },
    take: input.limit + 1,
    include: { members: { orderBy: { displayOrder: "asc" } } },
  });
  const hasMore = rows.length > input.limit;
  const page = rows.slice(0, input.limit);
  return {
    revision: manifest.revision,
    seasonId: manifest.seasonId,
    items: page.map((team) => ({
      teamKey: team.teamKey,
      members: team.members.map((member) => member.characterId),
      usageRate: team.usageRate,
      usageCount: team.usageCount,
      rank: team.rank,
      side: team.side,
      stageKey: team.stageKey,
      sampleSize: team.sampleSize,
    })),
    nextCursor: hasMore ? encodeCursor(page.at(-1)?.id) : null,
  };
}

export async function listPublishedCharacters(input: {
  contentType: BattleContentType;
  seasonId?: string;
  side?: string;
  limit: number;
  cursor?: string;
}) {
  const manifest = await publishedManifest(input.contentType, input.seasonId);
  if (!manifest) return null;
  const rows = await prisma.battleCharacterUsage.findMany({
    where: {
      snapshotId: manifest.publishedSnapshotId,
      isResolved: true,
      id: input.cursor ? { gt: input.cursor } : undefined,
      side: input.side,
    },
    orderBy: { id: "asc" },
    take: input.limit + 1,
  });
  const hasMore = rows.length > input.limit;
  const page = rows.slice(0, input.limit);
  return {
    revision: manifest.revision,
    seasonId: manifest.seasonId,
    items: page.map((character) => ({
      characterId: character.characterId,
      usageRate: character.usageRate,
      usageCount: character.usageCount,
      rank: character.rank,
      side: character.side,
      ownershipRate: character.ownershipRate,
      usageAmongOwnersRate: character.usageAmongOwnersRate,
      sampleSize: character.sampleSize,
    })),
    nextCursor: hasMore ? encodeCursor(page.at(-1)?.id) : null,
  };
}

export function encodeCursor(value: string | undefined): string | null {
  return value ? Buffer.from(value, "utf8").toString("base64url") : null;
}

export function decodeCursor(value: string | null): string | undefined {
  if (!value || value.length > 256) return undefined;
  try {
    const decoded = Buffer.from(value, "base64url").toString("utf8");
    return /^c[a-z0-9]{8,40}$/.test(decoded) ? decoded : undefined;
  } catch {
    return undefined;
  }
}

async function publishedManifest(
  contentType: BattleContentType,
  seasonId?: string,
) {
  const manifest = await prisma.battleStatsManifest.findUnique({
    where: { contentType },
  });
  return manifest && (!seasonId || manifest.seasonId === seasonId)
    ? manifest
    : null;
}

function manifestItem(
  row:
    | {
        seasonId: string;
        revision: number;
        payloadHash: string;
        updatedAt: Date;
      }
    | undefined,
): BattleStatsManifestItem | null {
  return row
    ? {
        seasonId: row.seasonId,
        revision: row.revision,
        payloadHash: row.payloadHash,
        updatedAt: row.updatedAt.toISOString(),
      }
    : null;
}
