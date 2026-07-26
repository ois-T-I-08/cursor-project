import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import {
  DeepSeekError,
  DeepSeekReplacementClient,
  type DeepSeekEvaluation,
} from "../team-recommendations/replacements/deepseek-client";
import { generateTemplateReplacements } from "../team-recommendations/replacements/generation-service";
import { LocalJsonTeamSource, ManualTeamSource } from "../team-recommendations/replacements/sources";
import {
  approveImportedTeam,
  getPublishedReplacement,
  getPublishedTemplates,
  importCharacterProfiles,
  importTeamsFromSource,
  overrideReplacementResult,
  setTemplatePublished,
} from "../team-recommendations/replacements/store";
import type {
  CharacterTeamProfile,
  ReplacementEvaluationInput,
} from "../team-recommendations/replacements/types";

const runDbTests = process.env.RUN_REPLACEMENT_DB_TEST === "true";
const ids = [
  "10000089",
  "10000052",
  "10000071",
  "10000058",
  "10000030",
  "10000031",
  "10000032",
  "10000033",
];

describe.runIf(runDbTests)("team template replacement database integration", () => {
  beforeAll(async () => {
    await clearReplacementData();
    await prisma.character.createMany({
      data: ids.map((id, index) => ({
        id,
        name: `Character ${index}`,
        element: ["pyro", "hydro", "anemo", "geo"][index % 4]!,
        weaponType: "sword",
        rarity: index % 2 ? 4 : 5,
        region: "test",
        iconUrl: "https://example.com/icon.png",
      })),
    });
  });

  afterAll(async () => {
    await clearReplacementData();
    await prisma.character.deleteMany({ where: { id: { in: ids } } });
    await prisma.$disconnect();
  });

  it("imports, deduplicates, generates, persists, publishes, and invalidates by version", async () => {
    expect(
      await importCharacterProfiles(profileCollection("profiles-v1")),
    ).toEqual({ imported: 8, rejected: 0 });
    const imported = await importTeamsFromSource(new LocalJsonTeamSource(
      `${process.cwd()}/data/team-templates/local-source.test.json`,
    ));
    expect(imported.created).toBe(1);

    const importedRow = await prisma.importedTeam.findFirstOrThrow({
      where: { sourceTeamId: "fixture-team" },
    });
    const templateId = await approveImportedTeam(importedRow.id);
    const generated = await generateTemplateReplacements(templateId, {
      client: new FakeDeepSeekClient(),
      modelIdentifier: "deepseek-v4-flash",
    });
    expect(generated.generated + generated.fallback).toBe(4);
    expect(await prisma.teamReplacementResult.count({ where: { templateId } })).toBe(4);

    await overrideReplacementResult({
      templateId,
      replacedCharacterId: "10000052",
      result: {
        slotAnalysis: {
          requiredFunctions: ["off_field_dps"],
          preferredFunctions: [],
          dependencies: [],
          replacementRisks: [],
        },
        candidates: [
          {
            characterId: "10000031",
            compatibilityScore: 82,
            category: "conditional",
            confidence: 0.8,
            reasons: ["管理者確認"],
            tradeoffs: [],
            requiredChanges: [],
            teamEvaluation: {
              reactionViability: 82,
              damageBalance: 82,
              sustain: 70,
              energy: 75,
              fieldTimeBalance: 85,
            },
          },
        ],
      },
    });
    expect(
      await prisma.teamReplacementResult.findFirstOrThrow({
        where: { templateId, replacedCharacterId: "10000052" },
        select: { errorCode: true },
      }),
    ).toEqual({ errorCode: "manualOverride" });

    await setTemplatePublished(templateId, true);
    expect(await getPublishedTemplates()).toHaveLength(1);
    const publishedReplacement = await getPublishedReplacement({
        templateId,
        replacedCharacterId: "10000052",
      });
    expect(publishedReplacement).not.toBeNull();
    expect(publishedReplacement).toMatchObject({ source: "manual" });

    const duplicate = await importTeamsFromSource(
      new ManualTeamSource([
        {
          source: "manual",
          sourceTeamId: "same-members",
          name: "Duplicate",
          characters: ["10000058", "10000071", "10000052", "10000089"].map(
            (characterId, slotIndex) => ({ characterId, slotIndex }),
          ),
          fetchedAt: "2026-07-26T00:00:00.000Z",
          dataVersion: "test-v1",
        },
      ]),
    );
    expect(duplicate.duplicates).toBe(1);
    const duplicateRow = await prisma.importedTeam.findUniqueOrThrow({
      where: {
        source_sourceTeamId: {
          source: "manual",
          sourceTeamId: "same-members",
        },
      },
    });
    expect(await approveImportedTeam(duplicateRow.id)).toBe(templateId);
    expect(
      await prisma.importedTeam.findUniqueOrThrow({
        where: { id: duplicateRow.id },
        select: { approvalStatus: true },
      }),
    ).toEqual({ approvalStatus: "duplicate" });

    expect(
      await importCharacterProfiles(profileCollection("profiles-v2")),
    ).toEqual({ imported: 8, rejected: 0 });
    await generateTemplateReplacements(templateId, {
      client: new FakeDeepSeekClient(),
      modelIdentifier: "deepseek-v4-flash",
    });
    expect(await prisma.teamReplacementResult.count({ where: { templateId } })).toBe(8);

    const failed = await generateTemplateReplacements(templateId, {
      force: true,
      client: new FailingDeepSeekClient(),
      modelIdentifier: "deepseek-v4-flash",
    });
    expect(failed.fallback).toBe(4);
    expect(await prisma.teamReplacementResult.count({ where: { templateId } })).toBe(8);

    const updated = await importTeamsFromSource(
      new ManualTeamSource([
        {
          source: "local",
          sourceTeamId: "fixture-team",
          name: "Updated template name",
          archetype: "updated",
          characters: ["10000089", "10000052", "10000071", "10000058"].map(
            (characterId, slotIndex) => ({ characterId, slotIndex }),
          ),
          fetchedAt: "2026-07-27T00:00:00.000Z",
          dataVersion: "test-v2",
        },
      ]),
    );
    expect(updated.updated).toBe(1);
    expect(
      await prisma.importedTeam.findUniqueOrThrow({
        where: {
          source_sourceTeamId: {
            source: "local",
            sourceTeamId: "fixture-team",
          },
        },
        select: { approvalStatus: true },
      }),
    ).toEqual({ approvalStatus: "pending_update" });
    expect(await approveImportedTeam(importedRow.id)).toBe(templateId);
    expect(await prisma.teamReplacementResult.count({ where: { templateId } })).toBe(0);
    expect(
      await prisma.teamTemplate.findUniqueOrThrow({
        where: { id: templateId },
        select: { status: true, name: true },
      }),
    ).toEqual({ status: "draft", name: "Updated template name" });
  });
});

class FakeDeepSeekClient extends DeepSeekReplacementClient {
  override async evaluate(input: ReplacementEvaluationInput): Promise<DeepSeekEvaluation> {
    return {
      modelIdentifier: "deepseek-v4-flash",
      attempts: 1,
      usage: { total_tokens: 20 },
      rawContent: JSON.stringify({ allowed: input.allowedCandidateIds }),
      result: {
        slotAnalysis: {
          requiredFunctions: input.evaluationRules.requiredFunctions,
          preferredFunctions: input.evaluationRules.preferredFunctions,
          dependencies: [],
          replacementRisks: [],
        },
        candidates: input.allowedCandidateIds.map((characterId) => ({
          characterId,
          compatibilityScore: 80,
          category: "conditional" as const,
          confidence: 0.8,
          reasons: ["structured"],
          tradeoffs: [],
          requiredChanges: [],
          teamEvaluation: {
            reactionViability: 80,
            damageBalance: 80,
            sustain: 70,
            energy: 70,
            fieldTimeBalance: 80,
          },
        })),
      },
    };
  }
}

class FailingDeepSeekClient extends DeepSeekReplacementClient {
  override async evaluate(): Promise<DeepSeekEvaluation> {
    throw new DeepSeekError("http503", true);
  }
}

function profileCollection(dataVersion: string) {
  return {
    gameVersion: "6.0",
    dataVersion,
    profiles: [
      profile("10000089", "pyro", ["main_dps"], ["on_field_dps"], "high", "on_field", dataVersion),
      profile("10000052", "hydro", ["sub_dps"], ["off_field_dps", "hydro_applier"], "low", "off_field", dataVersion),
      profile("10000071", "anemo", ["support"], ["buffer", "energy_battery"], "low", "off_field", dataVersion),
      profile("10000058", "geo", ["healer"], ["team_healer"], "low", "off_field", dataVersion, true),
      profile("10000030", "pyro", ["main_dps"], ["on_field_dps"], "high", "on_field", dataVersion),
      profile("10000031", "hydro", ["sub_dps"], ["off_field_dps", "hydro_applier"], "low", "off_field", dataVersion),
      profile("10000032", "anemo", ["support"], ["buffer", "energy_battery"], "low", "off_field", dataVersion),
      profile("10000033", "geo", ["healer"], ["team_healer"], "low", "off_field", dataVersion, true),
    ],
  };
}

function profile(
  characterId: string,
  element: string,
  roles: string[],
  tags: string[],
  fieldTime: CharacterTeamProfile["fieldTime"],
  damagePosition: CharacterTeamProfile["damagePosition"],
  dataVersion: string,
  healing = false,
): CharacterTeamProfile {
  return {
    characterId,
    element,
    roles,
    tags,
    fieldTime,
    damagePosition,
    application: { elements: [element], offField: damagePosition !== "on_field" },
    utility: healing ? { healing: "team" } : undefined,
    dataVersion,
  };
}

async function clearReplacementData(): Promise<void> {
  await prisma.teamReplacementCandidate.deleteMany();
  await prisma.teamReplacementResult.deleteMany();
  await prisma.teamReplacementJob.deleteMany();
  await prisma.teamTemplateMember.deleteMany();
  await prisma.teamTemplate.deleteMany();
  await prisma.importedTeamMember.deleteMany();
  await prisma.importedTeam.deleteMany();
  await prisma.characterTeamProfile.deleteMany();
  await prisma.teamImportLog.deleteMany();
}
