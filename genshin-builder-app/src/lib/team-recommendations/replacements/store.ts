import "server-only";

import { randomUUID } from "node:crypto";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/db";
import { buildEvaluationInput } from "./candidate-filter";
import { validateAndFinalizeReplacement } from "./final-validator";
import type {
  CharacterTeamProfile,
  NormalizedImportedTeam,
  ReplacementCacheIdentity,
  ReplacementResult,
  TeamSource,
} from "./types";
import { normalizeImportedTeam } from "./normalization";
import { replacementCacheKey } from "./replacement-cache-key";
import { parseCharacterTeamProfile, parseReplacementResult } from "./validation";
import {
  REPLACEMENT_PROMPT_VERSION,
  REPLACEMENT_RULES_VERSION,
} from "./versions";

export interface ImportSummary {
  created: number;
  updated: number;
  unchanged: number;
  duplicates: number;
  rejected: number;
}

export async function importTeamsFromSource(source: TeamSource): Promise<ImportSummary> {
  const rawTeams = await source.fetchTeams();
  const summary: ImportSummary = {
    created: 0,
    updated: 0,
    unchanged: 0,
    duplicates: 0,
    rejected: 0,
  };
  let sourceName = "unknown";

  for (const raw of rawTeams) {
    sourceName = raw.source;
    try {
      const normalized = normalizeImportedTeam(raw);
      const characterIds = normalized.characters.map((member) => member.characterId);
      const existingCharacters = await prisma.character.count({
        where: { id: { in: characterIds } },
      });
      if (existingCharacters !== 4) throw new Error("unknownCharacter");

      const previous = await prisma.importedTeam.findUnique({
        where: {
          source_sourceTeamId: {
            source: normalized.source,
            sourceTeamId: normalized.sourceTeamId,
          },
        },
        include: { template: { select: { id: true } } },
      });
      const duplicate = await prisma.importedTeam.findFirst({
        where: {
          teamHash: normalized.teamHash,
          NOT: previous ? { id: previous.id } : undefined,
        },
        select: { id: true },
      });
      const normalizedPayload = JSON.stringify(normalized);
      const changed = Boolean(previous && previous.normalizedPayload !== normalizedPayload);
      const approvalStatus = duplicate && !previous?.template
        ? "duplicate"
        : !previous
          ? "pending"
          : changed
            ? previous.template
              ? "pending_update"
              : "pending"
            : previous.approvalStatus;
      const imported = await prisma.$transaction(async (tx) => {
        const row = await tx.importedTeam.upsert({
          where: {
            source_sourceTeamId: {
              source: normalized.source,
              sourceTeamId: normalized.sourceTeamId,
            },
          },
          create: importedCreate(normalized, raw, normalizedPayload, approvalStatus),
          update: importedUpdate(normalized, raw, normalizedPayload, approvalStatus),
        });
        await tx.importedTeamMember.deleteMany({ where: { importedTeamId: row.id } });
        await tx.importedTeamMember.createMany({
          data: normalized.characters.map((member) => ({
            importedTeamId: row.id,
            characterId: member.characterId,
            sourceRole: member.sourceRole,
            normalizedRole: member.normalizedRole,
            slotIndex: member.slotIndex,
          })),
        });
        return row;
      });
      if (!previous) summary.created++;
      else if (!changed) summary.unchanged++;
      else summary.updated++;
      if (imported.approvalStatus === "duplicate") summary.duplicates++;
    } catch {
      summary.rejected++;
    }
  }
  await writeImportLog(sourceName, "import", summary.rejected ? "partial" : "success", summary);
  return summary;
}

export async function importCharacterProfiles(input: {
  gameVersion: string;
  dataVersion: string;
  profiles: CharacterTeamProfile[];
}): Promise<{ imported: number; rejected: number }> {
  let imported = 0;
  let rejected = 0;
  for (const rawProfile of input.profiles) {
    try {
      const profile = parseCharacterTeamProfile(rawProfile);
      if (profile.dataVersion !== input.dataVersion) throw new Error("profileVersionMismatch");
      const exists = await prisma.character.count({ where: { id: profile.characterId } });
      if (exists !== 1) throw new Error("unknownCharacter");
      await prisma.characterTeamProfile.upsert({
        where: { characterId: profile.characterId },
        create: {
          characterId: profile.characterId,
          payload: JSON.stringify(profile),
          dataVersion: input.dataVersion,
          gameVersion: input.gameVersion,
          isLeak: false,
        },
        update: {
          payload: JSON.stringify(profile),
          dataVersion: input.dataVersion,
          gameVersion: input.gameVersion,
          isLeak: false,
        },
      });
      imported++;
    } catch {
      rejected++;
    }
  }
  await writeImportLog("local", "profileImport", rejected ? "partial" : "success", {
    imported,
    rejected,
    dataVersion: input.dataVersion,
    gameVersion: input.gameVersion,
  });
  return { imported, rejected };
}

export async function approveImportedTeam(importedTeamId: string): Promise<string> {
  const imported = await prisma.importedTeam.findUnique({
    where: { id: importedTeamId },
    include: { members: { orderBy: { slotIndex: "asc" } }, template: true },
  });
  if (!imported || imported.members.length !== 4) throw new Error("importedTeamNotFound");
  if (imported.template && imported.approvalStatus !== "pending_update") {
    return imported.template.id;
  }
  const duplicate = await prisma.teamTemplate.findFirst({
    where: {
      teamHash: imported.teamHash,
      NOT: imported.template ? { id: imported.template.id } : undefined,
    },
    select: { id: true },
  });
  if (duplicate) {
    return markImportedTeamDuplicate(
      imported.id,
      imported.template?.id ?? null,
      duplicate.id,
    );
  }
  const profileCount = await prisma.characterTeamProfile.count({
    where: {
      characterId: { in: imported.members.map((member) => member.characterId) },
      isLeak: false,
    },
  });
  if (profileCount !== 4) throw new Error("teamProfilesIncomplete");

  try {
    return await prisma.$transaction(async (tx) => {
      if (imported.template) {
        await tx.teamReplacementResult.deleteMany({
          where: { templateId: imported.template.id },
        });
        await tx.teamReplacementJob.deleteMany({
          where: { templateId: imported.template.id },
        });
        await tx.teamTemplateMember.deleteMany({
          where: { templateId: imported.template.id },
        });
        const template = await tx.teamTemplate.update({
          where: { id: imported.template.id },
          data: {
            name: imported.name,
            archetype: imported.archetype,
            teamHash: imported.teamHash,
            dataVersion: imported.dataVersion,
            sourceUrl: imported.sourceUrl,
            status: "draft",
            publishedAt: null,
            members: {
              create: imported.members.map((member) => ({
                characterId: member.characterId,
                sourceRole: member.sourceRole,
                normalizedRole: member.normalizedRole,
                slotIndex: member.slotIndex,
              })),
            },
          },
        });
        await tx.importedTeam.update({
          where: { id: imported.id },
          data: { approvalStatus: "approved" },
        });
        return template.id;
      }
      const template = await tx.teamTemplate.create({
        data: {
          importedTeamId: imported.id,
          name: imported.name,
          archetype: imported.archetype,
          teamHash: imported.teamHash,
          dataVersion: imported.dataVersion,
          sourceUrl: imported.sourceUrl,
          members: {
            create: imported.members.map((member) => ({
              characterId: member.characterId,
              sourceRole: member.sourceRole,
              normalizedRole: member.normalizedRole,
              slotIndex: member.slotIndex,
            })),
          },
        },
      });
      await tx.importedTeam.update({
        where: { id: imported.id },
        data: { approvalStatus: "approved" },
      });
      return template.id;
    });
  } catch (error) {
    if (
      !(error instanceof Prisma.PrismaClientKnownRequestError) ||
      error.code !== "P2002"
    ) {
      throw error;
    }
    const ownTemplate = await prisma.teamTemplate.findUnique({
      where: { importedTeamId: imported.id },
      select: { id: true, teamHash: true },
    });
    if (ownTemplate?.teamHash === imported.teamHash) {
      await prisma.importedTeam.update({
        where: { id: imported.id },
        data: { approvalStatus: "approved" },
      });
      return ownTemplate.id;
    }
    const competingTemplate = await prisma.teamTemplate.findUnique({
      where: { teamHash: imported.teamHash },
      select: { id: true },
    });
    if (!competingTemplate) throw error;
    return markImportedTeamDuplicate(
      imported.id,
      ownTemplate?.id ?? imported.template?.id ?? null,
      competingTemplate.id,
    );
  }
}

export async function rejectImportedTeam(importedTeamId: string): Promise<void> {
  await prisma.importedTeam.update({
    where: { id: importedTeamId },
    data: { approvalStatus: "rejected" },
  });
}

export async function setTemplatePublished(
  templateId: string,
  published: boolean,
): Promise<void> {
  if (published) {
    const template = await prisma.teamTemplate.findUnique({
      where: { id: templateId },
      include: { members: true },
    });
    if (!template) throw new Error("templateNotFound");
    const results = await prisma.teamReplacementResult.findMany({
      where: { templateId, status: { in: ["validated", "fallback"] } },
      orderBy: { generatedAt: "desc" },
      select: { replacedCharacterId: true },
    });
    const covered = new Set(results.map((result) => result.replacedCharacterId));
    if (!template.members.every((member) => covered.has(member.characterId))) {
      throw new Error("replacementResultsIncomplete");
    }
  }
  await prisma.teamTemplate.update({
    where: { id: templateId },
    data: {
      status: published ? "published" : "draft",
      publishedAt: published ? new Date() : null,
    },
  });
}

export async function overrideReplacementResult(input: {
  templateId: string;
  replacedCharacterId: string;
  result: unknown;
}): Promise<ReplacementResult> {
  const template = await getTemplateForGeneration(input.templateId);
  if (!template.members.some((member) => member.characterId === input.replacedCharacterId)) {
    throw new Error("templateMemberNotFound");
  }
  const evaluationInput = buildEvaluationInput({
    gameDataVersion: template.gameVersion,
    team: template.members.map((member) => member.characterId),
    replacingCharacterId: input.replacedCharacterId,
    teamArchetype: template.archetype,
    profiles: template.profiles,
    maxCandidates: 20,
  });
  const finalized = validateAndFinalizeReplacement(
    input.result,
    evaluationInput,
    new Map(template.profiles.map((profile) => [profile.characterId, profile])),
  );
  const identity: ReplacementCacheIdentity = {
    teamHash: template.teamHash,
    replacedCharacterId: input.replacedCharacterId,
    gameDataVersion: template.gameVersion,
    characterDataVersion: template.characterDataVersion,
    promptVersion: REPLACEMENT_PROMPT_VERSION,
    rulesVersion: REPLACEMENT_RULES_VERSION,
    modelIdentifier:
      process.env.DEEPSEEK_MODEL?.trim() || "deepseek-v4-flash",
  };
  await saveReplacementResult({
    cacheKey: replacementCacheKey(identity),
    templateId: input.templateId,
    replacedCharacterId: input.replacedCharacterId,
    identity,
    status: "validated",
    rawAiOutput: "",
    result: finalized,
    errorCode: "manualOverride",
  });
  await prisma.teamTemplate.update({
    where: { id: input.templateId },
    data: {
      manualOverride: JSON.stringify({
        replacedCharacterId: input.replacedCharacterId,
        updatedAt: new Date().toISOString(),
      }),
    },
  });
  return finalized;
}

export async function getTemplateForGeneration(templateId: string): Promise<{
  id: string;
  name: string;
  archetype: string;
  teamHash: string;
  dataVersion: string;
  members: Array<{ characterId: string; normalizedRole: string; slotIndex: number }>;
  profiles: CharacterTeamProfile[];
  gameVersion: string;
  characterDataVersion: string;
}> {
  const template = await prisma.teamTemplate.findUnique({
    where: { id: templateId },
    include: { members: { orderBy: { slotIndex: "asc" } } },
  });
  if (!template) throw new Error("templateNotFound");
  const allRows = await prisma.characterTeamProfile.findMany({
    where: { isLeak: false },
    orderBy: { updatedAt: "desc" },
  });
  const newest = allRows[0];
  if (!newest) throw new Error("profilesUnavailable");
  const rows = allRows.filter(
    (row) =>
      row.gameVersion === newest.gameVersion &&
      row.dataVersion === newest.dataVersion,
  );
  const profiles = rows.map((row) => parseCharacterTeamProfile(JSON.parse(row.payload)));
  if (!template.members.every((member) => profiles.some((p) => p.characterId === member.characterId))) {
    throw new Error("teamProfilesIncomplete");
  }
  return {
    ...template,
    profiles,
    gameVersion: newest.gameVersion,
    characterDataVersion: newest.dataVersion,
  };
}

export async function findReplacementCache(cacheKey: string): Promise<ReplacementResult | null> {
  const row = await prisma.teamReplacementResult.findUnique({ where: { cacheKey } });
  if (!row || !["validated", "fallback"].includes(row.status)) return null;
  return parseReplacementResult(JSON.parse(row.validatedPayload));
}

export async function findLastGoodReplacement(
  templateId: string,
  replacedCharacterId: string,
): Promise<ReplacementResult | null> {
  const row = await prisma.teamReplacementResult.findFirst({
    where: {
      templateId,
      replacedCharacterId,
      status: { in: ["validated", "fallback"] },
    },
    orderBy: { generatedAt: "desc" },
  });
  return row ? parseReplacementResult(JSON.parse(row.validatedPayload)) : null;
}

export async function saveReplacementResult(input: {
  cacheKey: string;
  templateId: string;
  replacedCharacterId: string;
  identity: ReplacementCacheIdentity;
  status: "validated" | "fallback";
  rawAiOutput: string;
  result: ReplacementResult;
  errorCode?: string;
}): Promise<void> {
  await prisma.$transaction(async (tx) => {
    await tx.teamReplacementResult.upsert({
      where: { cacheKey: input.cacheKey },
      create: {
        cacheKey: input.cacheKey,
        templateId: input.templateId,
        ...input.identity,
        status: input.status,
        slotAnalysis: JSON.stringify(input.result.slotAnalysis),
        rawAiOutput: input.rawAiOutput,
        validatedPayload: JSON.stringify(input.result),
        errorCode: input.errorCode ?? "",
        generatedAt: new Date(),
      },
      update: {
        status: input.status,
        slotAnalysis: JSON.stringify(input.result.slotAnalysis),
        rawAiOutput: input.rawAiOutput,
        validatedPayload: JSON.stringify(input.result),
        errorCode: input.errorCode ?? "",
        generatedAt: new Date(),
      },
    });
    await tx.teamReplacementCandidate.deleteMany({ where: { resultKey: input.cacheKey } });
    if (input.result.candidates.length) {
      await tx.teamReplacementCandidate.createMany({
        data: input.result.candidates.map((candidate, index) => ({
          resultKey: input.cacheKey,
          characterId: candidate.characterId,
          compatibilityScore: Math.round(candidate.compatibilityScore),
          category: candidate.category,
          confidence: candidate.confidence,
          reasons: JSON.stringify(candidate.reasons),
          tradeoffs: JSON.stringify(candidate.tradeoffs),
          requiredChanges: JSON.stringify(candidate.requiredChanges),
          teamEvaluation: JSON.stringify(candidate.teamEvaluation),
          deterministicPenalty: candidate.deterministicPenalty ?? 0,
          finalScore: candidate.finalScore ?? Math.round(candidate.compatibilityScore),
          sortOrder: index,
        })),
      });
    }
  });
}

export async function createReplacementJob(templateId: string): Promise<string> {
  const id = randomUUID();
  await prisma.teamReplacementJob.create({
    data: { id, templateId, status: "running" },
  });
  return id;
}

export async function finishReplacementJob(
  id: string,
  data: {
    status: "completed" | "failed";
    attempts: number;
    cacheHits: number;
    successCount: number;
    failureCount: number;
    usage: Record<string, number>;
    errorCode?: string;
  },
): Promise<void> {
  await prisma.teamReplacementJob.update({
    where: { id },
    data: {
      status: data.status,
      attempts: data.attempts,
      cacheHits: data.cacheHits,
      successCount: data.successCount,
      failureCount: data.failureCount,
      usagePayload: JSON.stringify(data.usage),
      errorCode: data.errorCode ?? "",
      completedAt: new Date(),
    },
  });
}

export async function getAdminOverview(): Promise<object> {
  const [imports, templates, jobs, results, logs] = await Promise.all([
    prisma.importedTeam.findMany({
      orderBy: { updatedAt: "desc" },
      take: 100,
      include: { members: { orderBy: { slotIndex: "asc" } } },
    }),
    prisma.teamTemplate.findMany({
      orderBy: { updatedAt: "desc" },
      take: 100,
      include: { members: { orderBy: { slotIndex: "asc" } } },
    }),
    prisma.teamReplacementJob.findMany({ orderBy: { createdAt: "desc" }, take: 50 }),
    prisma.teamReplacementResult.findMany({
      orderBy: { generatedAt: "desc" },
      take: 100,
      select: {
        cacheKey: true,
        templateId: true,
        replacedCharacterId: true,
        modelIdentifier: true,
        promptVersion: true,
        rulesVersion: true,
        status: true,
        validatedPayload: true,
        errorCode: true,
        generatedAt: true,
      },
    }),
    prisma.teamImportLog.findMany({ orderBy: { createdAt: "desc" }, take: 50 }),
  ]);
  return { imports, templates, jobs, results, logs };
}

export async function getPublishedTemplates(): Promise<object[]> {
  const templates = await prisma.teamTemplate.findMany({
    where: { status: "published" },
    orderBy: [{ publishedAt: "desc" }, { name: "asc" }],
    take: 100,
    include: {
      members: { orderBy: { slotIndex: "asc" } },
      importedTeam: { select: { source: true, fetchedAt: true } },
    },
  });
  return templates.map((template) => ({
    id: template.id,
    name: template.name,
    archetype: template.archetype,
    members: template.members.map((member) => ({
      characterId: member.characterId,
      role: member.normalizedRole,
      slotIndex: member.slotIndex,
    })),
    source: template.importedTeam.source,
    sourceUrl: template.sourceUrl || null,
    dataVersion: template.dataVersion,
    updatedAt: template.updatedAt.toISOString(),
  }));
}

async function markImportedTeamDuplicate(
  importedTeamId: string,
  currentTemplateId: string | null,
  duplicateTemplateId: string,
): Promise<string> {
  await prisma.$transaction(async (tx) => {
    await tx.importedTeam.update({
      where: { id: importedTeamId },
      data: { approvalStatus: "duplicate" },
    });
    if (currentTemplateId && currentTemplateId !== duplicateTemplateId) {
      await tx.teamTemplate.update({
        where: { id: currentTemplateId },
        data: { status: "draft", publishedAt: null },
      });
    }
  });
  return duplicateTemplateId;
}

export async function getPublishedReplacement(input: {
  templateId: string;
  replacedCharacterId: string;
}): Promise<object | null> {
  const template = await prisma.teamTemplate.findFirst({
    where: {
      id: input.templateId,
      status: "published",
      members: { some: { characterId: input.replacedCharacterId } },
    },
  });
  if (!template) return null;
  const row = await prisma.teamReplacementResult.findFirst({
    where: {
      templateId: input.templateId,
      replacedCharacterId: input.replacedCharacterId,
      status: { in: ["validated", "fallback"] },
    },
    orderBy: { generatedAt: "desc" },
  });
  if (!row) return null;
  const payload = parseReplacementResult(JSON.parse(row.validatedPayload));
  const profileRows = await prisma.characterTeamProfile.findMany({
    where: {
      characterId: { in: payload.candidates.map((candidate) => candidate.characterId) },
      isLeak: false,
    },
  });
  const displayProfiles = new Map(
    profileRows.map((profile) => {
      const parsed = parseCharacterTeamProfile(JSON.parse(profile.payload));
      return [
        profile.characterId,
        { element: parsed.element, roles: parsed.roles, tags: parsed.tags },
      ];
    }),
  );
  const currentProfile = await prisma.characterTeamProfile.findFirst({
    where: { isLeak: false },
    orderBy: { updatedAt: "desc" },
    select: { gameVersion: true, dataVersion: true },
  });
  const expectedKey = currentProfile
    ? replacementCacheKey({
        teamHash: template.teamHash,
        replacedCharacterId: input.replacedCharacterId,
        gameDataVersion: currentProfile.gameVersion,
        characterDataVersion: currentProfile.dataVersion,
        promptVersion: REPLACEMENT_PROMPT_VERSION,
        rulesVersion: REPLACEMENT_RULES_VERSION,
        modelIdentifier:
          process.env.DEEPSEEK_MODEL?.trim() || "deepseek-v4-flash",
      })
    : null;
  return {
    templateId: input.templateId,
    replacedCharacterId: input.replacedCharacterId,
    generatedAt: row.generatedAt.toISOString(),
    dataVersion: row.characterDataVersion,
    isStale: expectedKey === null || row.cacheKey !== expectedKey,
    source:
      row.errorCode === "manualOverride"
        ? "manual"
        : row.status === "fallback"
          ? "rules"
          : "deepseek",
    slotAnalysis: payload.slotAnalysis,
    candidates: payload.candidates.map((candidate) => ({
      ...candidate,
      element: displayProfiles.get(candidate.characterId)?.element ?? "unknown",
      roles: displayProfiles.get(candidate.characterId)?.roles ?? [],
      tags: displayProfiles.get(candidate.characterId)?.tags ?? [],
    })),
  };
}

function importedCreate(
  team: NormalizedImportedTeam,
  raw: unknown,
  normalizedPayload: string,
  approvalStatus: string,
) {
  return {
    source: team.source,
    sourceTeamId: team.sourceTeamId,
    name: team.name,
    archetype: team.archetype ?? "",
    teamHash: team.teamHash,
    sourceUrl: team.sourceUrl ?? "",
    sourceUpdatedAt: team.sourceUpdatedAt ? new Date(team.sourceUpdatedAt) : null,
    fetchedAt: new Date(team.fetchedAt),
    rawPayload: JSON.stringify(raw),
    normalizedPayload,
    dataVersion: team.dataVersion,
    approvalStatus,
  };
}

function importedUpdate(
  team: NormalizedImportedTeam,
  raw: unknown,
  normalizedPayload: string,
  approvalStatus: string,
) {
  return importedCreate(team, raw, normalizedPayload, approvalStatus);
}

async function writeImportLog(
  source: string,
  action: string,
  status: string,
  detail: object,
): Promise<void> {
  await prisma.teamImportLog.create({
    data: { source, action, status, detail: JSON.stringify(detail) },
  });
}
