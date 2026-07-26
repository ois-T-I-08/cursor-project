import type {
  CharacterTeamProfile,
  ReplacementEvaluationInput,
} from "./types";

export interface PrefilteredCandidate {
  profile: CharacterTeamProfile;
  ruleScore: number;
  matchedFunctions: string[];
  missingFunctions: string[];
}

export function buildEvaluationInput(input: {
  gameDataVersion: string;
  team: string[];
  replacingCharacterId: string;
  teamArchetype: string;
  profiles: CharacterTeamProfile[];
  maxCandidates?: number;
}): ReplacementEvaluationInput {
  const byId = new Map(input.profiles.map((profile) => [profile.characterId, profile]));
  const original = byId.get(input.replacingCharacterId);
  if (!original || input.team.length !== 4 || !input.team.includes(input.replacingCharacterId)) {
    throw new Error("replacementProfileUnavailable");
  }
  const remaining = input.team
    .filter((id) => id !== input.replacingCharacterId)
    .map((id) => byId.get(id))
    .filter((profile): profile is CharacterTeamProfile => Boolean(profile));
  if (remaining.length !== 3) throw new Error("teamProfilesIncomplete");

  const evaluationRules = deriveRules(original, remaining);
  const maxCandidates = Math.min(20, Math.max(10, input.maxCandidates ?? 16));
  const filtered = prefilterReplacementCandidates({
    team: input.team,
    original,
    remaining,
    profiles: input.profiles,
    maxCandidates,
    requiredFunctions: evaluationRules.requiredFunctions,
    requiredElements: evaluationRules.requiredElements,
  });
  return {
    gameDataVersion: input.gameDataVersion,
    team: input.team,
    replacingCharacterId: input.replacingCharacterId,
    teamArchetype: input.teamArchetype,
    originalCharacterProfile: original,
    remainingCharacterProfiles: remaining,
    candidateProfiles: filtered.map((candidate) => candidate.profile),
    allowedCandidateIds: filtered.map((candidate) => candidate.profile.characterId),
    evaluationRules,
  };
}

export function prefilterReplacementCandidates(input: {
  team: string[];
  original: CharacterTeamProfile;
  remaining: CharacterTeamProfile[];
  profiles: CharacterTeamProfile[];
  requiredFunctions: string[];
  requiredElements: string[];
  maxCandidates: number;
}): PrefilteredCandidate[] {
  const excluded = new Set(input.team);
  return input.profiles
    .filter((candidate) => !excluded.has(candidate.characterId))
    .map((candidate) => scoreCandidate(candidate, input))
    .filter((candidate) => candidate.ruleScore > 0)
    .sort(
      (a, b) =>
        b.ruleScore - a.ruleScore ||
        a.profile.characterId.localeCompare(b.profile.characterId),
    )
    .slice(0, Math.min(20, Math.max(0, input.maxCandidates)));
}

function deriveRules(
  original: CharacterTeamProfile,
  remaining: CharacterTeamProfile[],
): ReplacementEvaluationInput["evaluationRules"] {
  const remainingTags = new Set(remaining.flatMap((profile) => profile.tags));
  const requiredFunctions = original.tags.filter((tag) => {
    if (tag === "on_field_dps" || tag === "high_field_time") return true;
    return !remainingTags.has(tag);
  });
  const remainingApplications = new Set(
    remaining.flatMap((profile) => profile.application?.elements ?? []),
  );
  const requiredElements = (original.application?.elements ?? []).filter(
    (element) => !remainingApplications.has(element),
  );
  const requiresSustain =
    Boolean(original.utility?.healing || original.utility?.shielding) &&
    !remaining.some((profile) => profile.utility?.healing || profile.utility?.shielding);
  return {
    requiredFunctions,
    preferredFunctions: [...new Set([...original.roles, ...original.tags])],
    requiredElements,
    requiresSustain,
    maxOnFieldCharacters: 1,
  };
}

function scoreCandidate(
  candidate: CharacterTeamProfile,
  input: {
    original: CharacterTeamProfile;
    remaining: CharacterTeamProfile[];
    requiredFunctions: string[];
    requiredElements: string[];
  },
): PrefilteredCandidate {
  const functions = new Set([...candidate.roles, ...candidate.tags]);
  const required = input.requiredFunctions;
  const matchedFunctions = required.filter((value) => functions.has(value));
  const missingFunctions = required.filter((value) => !functions.has(value));
  const roleOverlap = intersectionSize(candidate.roles, input.original.roles);
  const tagOverlap = intersectionSize(candidate.tags, input.original.tags);
  const elementMatches =
    input.requiredElements.length === 0 ||
    input.requiredElements.some(
      (element) =>
        candidate.element === element ||
        candidate.application?.elements.includes(element),
    );
  let score = roleOverlap * 18 + tagOverlap * 6 + matchedFunctions.length * 12;
  if (candidate.damagePosition === input.original.damagePosition) score += 12;
  if (candidate.fieldTime === input.original.fieldTime) score += 8;
  if (candidate.element === input.original.element) score += 5;
  if (elementMatches) score += 12;
  else score -= 24;
  if (
    (input.original.utility?.healing && candidate.utility?.healing) ||
    (input.original.utility?.shielding && candidate.utility?.shielding)
  ) {
    score += 18;
  }
  if (
    candidate.fieldTime === "high" &&
    input.remaining.some((profile) => profile.fieldTime === "high")
  ) {
    score -= 20;
  }
  return {
    profile: candidate,
    ruleScore: Math.max(0, score),
    matchedFunctions,
    missingFunctions,
  };
}

function intersectionSize(a: string[], b: string[]): number {
  const values = new Set(b);
  return a.reduce((count, value) => count + (values.has(value) ? 1 : 0), 0);
}
