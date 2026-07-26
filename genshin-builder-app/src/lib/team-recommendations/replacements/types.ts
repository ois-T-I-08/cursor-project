export const TEAM_SOURCES = ["genshinbuilds", "local", "manual"] as const;
export type TeamSourceName = (typeof TEAM_SOURCES)[number];

export const NORMALIZED_TEAM_ROLES = [
  "main_dps",
  "sub_dps",
  "support",
  "healer",
  "shielder",
  "flex",
] as const;
export type NormalizedTeamRole = (typeof NORMALIZED_TEAM_ROLES)[number];

export interface ImportedTeamMemberInput {
  characterId: string;
  sourceRole?: string;
  slotIndex: number;
}

export interface ImportedTeam {
  source: TeamSourceName;
  sourceTeamId: string;
  name: string;
  archetype?: string;
  characters: ImportedTeamMemberInput[];
  sourceUrl?: string;
  sourceUpdatedAt?: string;
  fetchedAt: string;
  dataVersion: string;
}

export interface NormalizedTeamMember {
  characterId: string;
  sourceRole: string;
  normalizedRole: NormalizedTeamRole;
  slotIndex: number;
}

export interface NormalizedImportedTeam extends Omit<ImportedTeam, "characters"> {
  characters: NormalizedTeamMember[];
  teamHash: string;
}

export interface TeamSource {
  fetchTeams(): Promise<ImportedTeam[]>;
}

export type FieldTime = "none" | "low" | "medium" | "high";
export type DamagePosition = "on_field" | "off_field" | "both" | "none";

export interface CharacterTeamProfile {
  characterId: string;
  element: string;
  weaponType?: string;
  roles: string[];
  tags: string[];
  fieldTime: FieldTime;
  damagePosition: DamagePosition;
  application?: {
    elements: string[];
    strength?: string;
    frequency?: string;
    offField: boolean;
  };
  triggers?: string[];
  utility?: {
    healing?: string;
    shielding?: string;
    interruptionResistance?: boolean;
    damageReduction?: boolean;
    grouping?: boolean;
    energyGeneration?: string;
  };
  buffs?: {
    targets?: string[];
    types?: string[];
  };
  restrictions?: string[];
  dataVersion: string;
}

export interface ReplacementEvaluationInput {
  gameDataVersion: string;
  team: string[];
  replacingCharacterId: string;
  teamArchetype: string;
  originalCharacterProfile: CharacterTeamProfile;
  remainingCharacterProfiles: CharacterTeamProfile[];
  candidateProfiles: CharacterTeamProfile[];
  allowedCandidateIds: string[];
  evaluationRules: {
    requiredFunctions: string[];
    preferredFunctions: string[];
    requiredElements: string[];
    requiresSustain: boolean;
    maxOnFieldCharacters: number;
  };
}

export type ReplacementCategory =
  | "optimal"
  | "conditional"
  | "compromise"
  | "not_recommended";

export interface TeamEvaluation {
  reactionViability: number;
  damageBalance: number;
  sustain: number;
  energy: number;
  fieldTimeBalance: number;
}

export interface ReplacementCandidateEvaluation {
  characterId: string;
  compatibilityScore: number;
  category: ReplacementCategory;
  confidence: number;
  reasons: string[];
  tradeoffs: string[];
  requiredChanges: string[];
  teamEvaluation: TeamEvaluation;
  deterministicPenalty?: number;
  finalScore?: number;
}

export interface ReplacementResult {
  slotAnalysis: {
    requiredFunctions: string[];
    preferredFunctions: string[];
    dependencies: string[];
    replacementRisks: string[];
  };
  candidates: ReplacementCandidateEvaluation[];
}

export interface ReplacementCacheIdentity {
  teamHash: string;
  replacedCharacterId: string;
  gameDataVersion: string;
  characterDataVersion: string;
  promptVersion: string;
  rulesVersion: string;
  modelIdentifier: string;
}
