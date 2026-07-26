import type {
  CharacterTeamProfile,
  ReplacementCandidateEvaluation,
  ReplacementEvaluationInput,
  ReplacementResult,
} from "./types";
import { parseAiReplacementResult } from "./validation";

export function validateAndFinalizeReplacement(
  raw: unknown,
  input: ReplacementEvaluationInput,
  knownProfiles: Map<string, CharacterTeamProfile>,
): ReplacementResult {
  const parsed = parseAiReplacementResult(raw);
  const allowed = new Set(input.allowedCandidateIds);
  const seen = new Set<string>();
  const candidates: ReplacementCandidateEvaluation[] = [];

  for (const candidate of parsed.candidates) {
    if (!allowed.has(candidate.characterId) || seen.has(candidate.characterId)) continue;
    const profile = knownProfiles.get(candidate.characterId);
    if (!profile || input.team.includes(candidate.characterId)) continue;
    if (profile.dataVersion !== input.originalCharacterProfile.dataVersion) continue;
    seen.add(candidate.characterId);
    candidates.push(applyDeterministicRules(candidate, profile, input));
  }

  candidates.sort(
    (a, b) =>
      (b.finalScore ?? 0) - (a.finalScore ?? 0) ||
      b.confidence - a.confidence ||
      a.characterId.localeCompare(b.characterId),
  );
  return { slotAnalysis: parsed.slotAnalysis, candidates };
}

function applyDeterministicRules(
  candidate: ReplacementCandidateEvaluation,
  profile: CharacterTeamProfile,
  input: ReplacementEvaluationInput,
): ReplacementCandidateEvaluation {
  const replacementTeam = [
    ...input.remainingCharacterProfiles,
    profile,
  ];
  let penalty = 0;
  const tradeoffs = [...candidate.tradeoffs];
  const requiredChanges = [...candidate.requiredChanges];
  const highFieldCount = replacementTeam.filter(
    (member) => member.fieldTime === "high",
  ).length;
  if (highFieldCount > input.evaluationRules.maxOnFieldCharacters) {
    penalty += 25;
    pushLimited(tradeoffs, "オンフィールド時間が競合します");
  }
  if (
    input.evaluationRules.requiredElements.length > 0 &&
    !input.evaluationRules.requiredElements.some((element) =>
      replacementTeam.some(
        (member) =>
          member.element === element ||
          member.application?.elements.includes(element),
      ),
    )
  ) {
    penalty += 40;
    pushLimited(tradeoffs, "必要な元素付着を維持できません");
  }
  if (
    input.evaluationRules.requiresSustain &&
    !replacementTeam.some(
      (member) => member.utility?.healing || member.utility?.shielding,
    )
  ) {
    penalty += 35;
    pushLimited(requiredChanges, "回復役またはシールド役を別枠で確保してください");
  }
  if (
    profile.tags.includes("burst_dependent") &&
    !replacementTeam.some((member) => member.tags.includes("energy_battery"))
  ) {
    penalty += 10;
    pushLimited(tradeoffs, "元素エネルギーの確保が難しくなります");
  }
  for (const restriction of profile.restrictions ?? []) {
    if (!restriction.startsWith("requires_tag:")) continue;
    const requiredTag = restriction.slice("requires_tag:".length);
    if (!replacementTeam.some((member) => member.tags.includes(requiredTag))) {
      penalty += 20;
      pushLimited(requiredChanges, `必要条件「${requiredTag}」を満たしてください`);
    }
  }
  const finalScore = Math.max(0, Math.round(candidate.compatibilityScore - penalty));
  return {
    ...candidate,
    category: categoryForScore(finalScore),
    tradeoffs,
    requiredChanges,
    deterministicPenalty: penalty,
    finalScore,
  };
}

function categoryForScore(score: number): ReplacementCandidateEvaluation["category"] {
  if (score >= 85) return "optimal";
  if (score >= 65) return "conditional";
  if (score >= 45) return "compromise";
  return "not_recommended";
}

function pushLimited(values: string[], value: string): void {
  if (!values.includes(value) && values.length < 3) values.push(value);
}
