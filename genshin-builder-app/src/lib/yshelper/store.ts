import { Prisma } from "@prisma/client";

import { prisma } from "@/lib/db";
import type {
  BattleContentType,
  BattleValidationIssue,
  BattleValidationState,
  NormalizedBattleStats,
} from "./types";

export interface BattleStatsRunSummary {
  id: string;
  finishedAt: Date;
}

export interface BattleStatsSnapshotWriteResult {
  snapshotId: string;
  revision: number;
  duplicate: boolean;
  published: boolean;
}

export interface BattleStatsStore {
  findLastSuccessfulRun(): Promise<BattleStatsRunSummary | null>;
  createRun(
    attemptedContentTypes: BattleContentType[],
    previousSuccessfulRunId: string | null,
    lastSuccessfulAt: Date | null,
    startedAt: Date,
  ): Promise<string>;
  finishRun(
    runId: string,
    input: {
      status: string;
      finishedAt: Date;
      responseStatus?: number;
      sourceVersion?: string;
      payloadHash?: string;
      recordCount: number;
      validationState: BattleValidationState | "pending";
      validationErrors: BattleValidationIssue[];
      errorCode?: string;
      errorDetail?: string;
    },
  ): Promise<void>;
  knownCharacterIds(): Promise<Set<string>>;
  loadPublished(
    contentType: BattleContentType,
  ): Promise<NormalizedBattleStats | null>;
  saveSnapshot(
    runId: string,
    value: NormalizedBattleStats,
    payloadHash: string,
    validationState: BattleValidationState,
    issues: BattleValidationIssue[],
    now: Date,
  ): Promise<BattleStatsSnapshotWriteResult>;
}

export class PrismaBattleStatsStore implements BattleStatsStore {
  async findLastSuccessfulRun(): Promise<BattleStatsRunSummary | null> {
    const row = await prisma.battleStatsSyncRun.findFirst({
      where: { source: "YShelper", status: "success", finishedAt: { not: null } },
      orderBy: { finishedAt: "desc" },
      select: { id: true, finishedAt: true },
    });
    return row?.finishedAt ? { id: row.id, finishedAt: row.finishedAt } : null;
  }

  async createRun(
    attemptedContentTypes: BattleContentType[],
    previousSuccessfulRunId: string | null,
    lastSuccessfulAt: Date | null,
    startedAt: Date,
  ): Promise<string> {
    const row = await prisma.battleStatsSyncRun.create({
      data: {
        source: "YShelper",
        status: "running",
        startedAt,
        lastSuccessfulAt,
        previousSuccessfulRunId,
        attemptedContentTypes: toJson(attemptedContentTypes),
        validationState: "pending",
        validationErrors: [],
      },
      select: { id: true },
    });
    return row.id;
  }

  async finishRun(
    runId: string,
    input: {
      status: string;
      finishedAt: Date;
      responseStatus?: number;
      sourceVersion?: string;
      payloadHash?: string;
      recordCount: number;
      validationState: BattleValidationState | "pending";
      validationErrors: BattleValidationIssue[];
      errorCode?: string;
      errorDetail?: string;
    },
  ): Promise<void> {
    await prisma.battleStatsSyncRun.update({
      where: { id: runId },
      data: {
        status: input.status,
        finishedAt: input.finishedAt,
        responseStatus: input.responseStatus,
        sourceVersion: input.sourceVersion,
        payloadHash: input.payloadHash,
        recordCount: input.recordCount,
        validationState: input.validationState,
        validationErrors: toJson(input.validationErrors),
        errorCode: input.errorCode,
        errorDetail: input.errorDetail,
      },
    });
  }

  async knownCharacterIds(): Promise<Set<string>> {
    const rows = await prisma.character.findMany({ select: { id: true } });
    return new Set(rows.map((row) => row.id));
  }

  async loadPublished(
    contentType: BattleContentType,
  ): Promise<NormalizedBattleStats | null> {
    const manifest = await prisma.battleStatsManifest.findUnique({
      where: { contentType },
      include: {
        publishedSnapshot: {
          include: {
            teamUsages: {
              include: { members: { orderBy: { displayOrder: "asc" } } },
            },
            characterUsage: true,
          },
        },
      },
    });
    if (!manifest) return null;
    return snapshotToNormalized(manifest.publishedSnapshot);
  }

  async saveSnapshot(
    runId: string,
    value: NormalizedBattleStats,
    payloadHash: string,
    validationState: BattleValidationState,
    issues: BattleValidationIssue[],
    now: Date,
  ): Promise<BattleStatsSnapshotWriteResult> {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.battleStatsSnapshot.findUnique({
        where: {
          source_contentType_seasonId_payloadHash: {
            source: value.source,
            contentType: value.contentType,
            seasonId: value.seasonId,
            payloadHash,
          },
        },
        select: { id: true, revision: true, publishedAt: true },
      });
      if (existing) {
        return {
          snapshotId: existing.id,
          revision: existing.revision,
          duplicate: true,
          published: existing.publishedAt !== null,
        };
      }

      const previous = await tx.battleStatsSnapshot.findFirst({
        where: { contentType: value.contentType },
        orderBy: { revision: "desc" },
        select: { revision: true },
      });
      const revision = (previous?.revision ?? 0) + 1;
      const publish = validationState === "valid";
      const snapshot = await tx.battleStatsSnapshot.create({
        data: {
          source: value.source,
          contentType: value.contentType,
          seasonId: value.seasonId,
          revision,
          schemaVersion: value.schemaVersion,
          payloadHash,
          sourceVersion: value.sourceVersion,
          sourceUpdatedAt: new Date(value.sourceUpdatedAt),
          fetchedAt: now,
          validatedAt: now,
          publishedAt: publish ? now : null,
          validationState,
          sampleSize: value.sampleSize,
          metadata: toJson({
            validationIssues: issues.map((issue) => issue.code),
          }),
          syncRunId: runId,
          teamUsages: {
            create: value.teams.map((team) => ({
              teamKey: team.teamKey,
              usageRate: team.usageRate,
              usageCount: team.usageCount,
              rank: team.rank,
              side: team.side,
              stageKey: team.stageKey,
              scopeKey: `${team.side ?? ""}|${team.stageKey ?? ""}`,
              sampleSize: team.sampleSize,
              isResolved: team.isResolved,
              sourceMetadata: {},
              members: {
                create: team.members.map((characterId, index) => ({
                  characterId,
                  slot: index,
                  displayOrder: index,
                })),
              },
            })),
          },
          characterUsage: {
            create: value.characters.map((character) => ({
              characterId: character.characterId,
              usageRate: character.usageRate,
              usageCount: character.usageCount,
              rank: character.rank,
              side: character.side,
              scopeKey: character.side ?? "",
              ownershipRate: character.ownershipRate,
              usageAmongOwnersRate: character.usageAmongOwnersRate,
              sampleSize: character.sampleSize,
              isResolved: character.isResolved,
            })),
          },
        },
        select: { id: true },
      });

      if (publish) {
        await tx.battleStatsManifest.upsert({
          where: { contentType: value.contentType },
          create: {
            contentType: value.contentType,
            publishedSnapshotId: snapshot.id,
            revision,
            payloadHash,
            schemaVersion: value.schemaVersion,
            seasonId: value.seasonId,
          },
          update: {
            publishedSnapshotId: snapshot.id,
            revision,
            payloadHash,
            schemaVersion: value.schemaVersion,
            seasonId: value.seasonId,
          },
        });
      }

      return {
        snapshotId: snapshot.id,
        revision,
        duplicate: false,
        published: publish,
      };
    });
  }
}

function snapshotToNormalized(snapshot: {
  source: string;
  contentType: string;
  schemaVersion: number;
  sourceVersion: string | null;
  seasonId: string;
  sourceUpdatedAt: Date;
  sampleSize: number | null;
  teamUsages: Array<{
    teamKey: string;
    usageRate: number;
    usageCount: number | null;
    rank: number | null;
    side: string | null;
    stageKey: string | null;
    sampleSize: number | null;
    isResolved: boolean;
    members: Array<{ characterId: string }>;
  }>;
  characterUsage: Array<{
    characterId: string;
    usageRate: number;
    usageCount: number | null;
    rank: number | null;
    side: string | null;
    ownershipRate: number | null;
    usageAmongOwnersRate: number | null;
    sampleSize: number | null;
    isResolved: boolean;
  }>;
}): NormalizedBattleStats {
  return {
    source: "YShelper",
    contentType: snapshot.contentType as BattleContentType,
    schemaVersion: 1,
    sourceVersion: snapshot.sourceVersion ?? "unknown",
    seasonId: snapshot.seasonId,
    sourceUpdatedAt: snapshot.sourceUpdatedAt.toISOString(),
    sampleSize: snapshot.sampleSize ?? undefined,
    metadata: {},
    teams: snapshot.teamUsages.map((team) => ({
      teamKey: team.teamKey,
      members: team.members.map((member) => member.characterId),
      usageRate: team.usageRate,
      usageCount: team.usageCount ?? undefined,
      rank: team.rank ?? undefined,
      side: team.side ?? undefined,
      stageKey: team.stageKey ?? undefined,
      sampleSize: team.sampleSize ?? undefined,
      isResolved: team.isResolved,
      sourceMetadata: {},
    })),
    characters: snapshot.characterUsage.map((character) => ({
      characterId: character.characterId,
      usageRate: character.usageRate,
      usageCount: character.usageCount ?? undefined,
      rank: character.rank ?? undefined,
      side: character.side ?? undefined,
      ownershipRate: character.ownershipRate ?? undefined,
      usageAmongOwnersRate: character.usageAmongOwnersRate ?? undefined,
      sampleSize: character.sampleSize ?? undefined,
      isResolved: character.isResolved,
    })),
  };
}

function toJson(value: unknown): Prisma.InputJsonValue {
  return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
}
