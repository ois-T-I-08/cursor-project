import "server-only";

import { buildEvaluationInput } from "./candidate-filter";
import {
  DeepSeekError,
  DeepSeekReplacementClient,
} from "./deepseek-client";
import { validateAndFinalizeReplacement } from "./final-validator";
import { replacementCacheKey } from "./replacement-cache-key";
import {
  createReplacementJob,
  findLastGoodReplacement,
  findReplacementCache,
  finishReplacementJob,
  getTemplateForGeneration,
  saveReplacementResult,
} from "./store";
import type {
  CharacterTeamProfile,
  ReplacementCacheIdentity,
  ReplacementEvaluationInput,
  ReplacementResult,
} from "./types";
import {
  REPLACEMENT_PROMPT_VERSION,
  REPLACEMENT_RULES_VERSION,
} from "./versions";

export { REPLACEMENT_RULES_VERSION };

export interface GenerationSummary {
  jobId: string;
  cacheHits: number;
  generated: number;
  fallback: number;
  failed: number;
}

export async function generateTemplateReplacements(
  templateId: string,
  options: {
    force?: boolean;
    client?: DeepSeekReplacementClient;
    modelIdentifier?: string;
  } = {},
): Promise<GenerationSummary> {
  const template = await getTemplateForGeneration(templateId);
  const jobId = await createReplacementJob(templateId);
  const summary: GenerationSummary = {
    jobId,
    cacheHits: 0,
    generated: 0,
    fallback: 0,
    failed: 0,
  };
  const usage: Record<string, number> = {};
  let attempts = 0;
  const client = options.client ?? new DeepSeekReplacementClient();
  const configuredModel =
    options.modelIdentifier ??
    process.env.DEEPSEEK_MODEL?.trim() ??
    "deepseek-v4-flash";

  try {
    const team = template.members.map((member) => member.characterId);
    const profileMap = new Map(
      template.profiles.map((profile) => [profile.characterId, profile]),
    );
    for (const member of template.members) {
      const identity: ReplacementCacheIdentity = {
        teamHash: template.teamHash,
        replacedCharacterId: member.characterId,
        gameDataVersion: template.gameVersion,
        characterDataVersion: template.characterDataVersion,
        promptVersion: REPLACEMENT_PROMPT_VERSION,
        rulesVersion: REPLACEMENT_RULES_VERSION,
        modelIdentifier: configuredModel,
      };
      const cacheKey = replacementCacheKey(identity);
      if (!options.force && (await findReplacementCache(cacheKey))) {
        summary.cacheHits++;
        continue;
      }
      const evaluationInput = buildEvaluationInput({
        gameDataVersion: template.gameVersion,
        team,
        replacingCharacterId: member.characterId,
        teamArchetype: template.archetype,
        profiles: template.profiles,
        maxCandidates: configuredCandidateLimit(),
      });

      try {
        if (evaluationInput.allowedCandidateIds.length === 0) {
          const empty = emptyReplacementResult(evaluationInput);
          await saveReplacementResult({
            cacheKey,
            templateId,
            replacedCharacterId: member.characterId,
            identity,
            status: "fallback",
            rawAiOutput: "",
            result: empty,
            errorCode: "noCandidates",
          });
          summary.fallback++;
          continue;
        }
        const evaluation = await client.evaluate(evaluationInput);
        attempts += evaluation.attempts;
        addUsage(usage, evaluation.usage);
        const finalized = validateAndFinalizeReplacement(
          evaluation.result,
          evaluationInput,
          profileMap,
        );
        await saveReplacementResult({
          cacheKey,
          templateId,
          replacedCharacterId: member.characterId,
          identity: { ...identity, modelIdentifier: evaluation.modelIdentifier },
          status: "validated",
          rawAiOutput: evaluation.rawContent,
          result: finalized,
        });
        summary.generated++;
      } catch (error) {
        summary.failed++;
        const code = error instanceof DeepSeekError ? error.code : "generationFailed";
        const lastGood = await findLastGoodReplacement(templateId, member.characterId);
        if (lastGood) {
          summary.cacheHits++;
          summary.fallback++;
          continue;
        }
        const fallback = validateAndFinalizeReplacement(
          ruleBasedResult(evaluationInput),
          evaluationInput,
          profileMap,
        );
        await saveReplacementResult({
          cacheKey,
          templateId,
          replacedCharacterId: member.characterId,
          identity,
          status: "fallback",
          rawAiOutput: "",
          result: fallback,
          errorCode: code,
        });
        summary.fallback++;
      }
    }
    await finishReplacementJob(jobId, {
      status: "completed",
      attempts,
      cacheHits: summary.cacheHits,
      successCount: summary.generated + summary.fallback,
      failureCount: summary.failed,
      usage,
    });
    return summary;
  } catch (error) {
    summary.failed++;
    await finishReplacementJob(jobId, {
      status: "failed",
      attempts,
      cacheHits: summary.cacheHits,
      successCount: summary.generated + summary.fallback,
      failureCount: summary.failed,
      usage,
      errorCode: safeErrorCode(error),
    });
    throw error;
  }
}

function ruleBasedResult(input: ReplacementEvaluationInput): ReplacementResult {
  return {
    slotAnalysis: {
      requiredFunctions: input.evaluationRules.requiredFunctions,
      preferredFunctions: input.evaluationRules.preferredFunctions,
      dependencies: [],
      replacementRisks: ["AI評価を利用できないため構造化プロフィールだけで評価しています"],
    },
    candidates: input.candidateProfiles.map((profile) => {
      const compatibility = ruleCompatibility(input.originalCharacterProfile, profile);
      return {
        characterId: profile.characterId,
        compatibilityScore: compatibility,
        category: "conditional" as const,
        confidence: 0.45,
        reasons: ["役割・タグ・攻撃位置の一致度に基づく候補です"],
        tradeoffs: ["AIによる編成全体評価は未実施です"],
        requiredChanges: [],
        teamEvaluation: {
          reactionViability: compatibility,
          damageBalance: compatibility,
          sustain: profile.utility?.healing || profile.utility?.shielding ? 75 : 50,
          energy: profile.utility?.energyGeneration ? 70 : 50,
          fieldTimeBalance:
            profile.fieldTime === input.originalCharacterProfile.fieldTime ? 75 : 50,
        },
      };
    }),
  };
}

function emptyReplacementResult(input: ReplacementEvaluationInput): ReplacementResult {
  return {
    slotAnalysis: {
      requiredFunctions: input.evaluationRules.requiredFunctions,
      preferredFunctions: input.evaluationRules.preferredFunctions,
      dependencies: [],
      replacementRisks: ["構造化プロフィールから安全な候補を抽出できませんでした"],
    },
    candidates: [],
  };
}

function ruleCompatibility(
  original: CharacterTeamProfile,
  candidate: CharacterTeamProfile,
): number {
  const roles = new Set(original.roles);
  const tags = new Set(original.tags);
  let score = 35;
  score += candidate.roles.filter((value) => roles.has(value)).length * 15;
  score += candidate.tags.filter((value) => tags.has(value)).length * 5;
  if (candidate.damagePosition === original.damagePosition) score += 10;
  if (candidate.fieldTime === original.fieldTime) score += 5;
  return Math.min(85, score);
}

function configuredCandidateLimit(): number {
  const value = Number(process.env.TEAM_REPLACEMENT_MAX_CANDIDATES);
  return Number.isFinite(value) ? Math.min(20, Math.max(10, Math.round(value))) : 16;
}

function addUsage(target: Record<string, number>, source: Record<string, number>): void {
  for (const [key, value] of Object.entries(source)) {
    target[key] = (target[key] ?? 0) + value;
  }
}

function safeErrorCode(error: unknown): string {
  if (error instanceof DeepSeekError) return error.code;
  if (error instanceof Error && /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message)) {
    return error.message;
  }
  return "generationFailed";
}
