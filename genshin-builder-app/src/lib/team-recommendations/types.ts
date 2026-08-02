import type { AbyssTeamStatistic } from "@/lib/abyss/types";

export type InputQuality = "exact" | "partial" | "defaulted" | "unsupported";
export type Element = "anemo" | "cryo" | "dendro" | "electro" | "geo" | "hydro" | "pyro";
export type SimulationStatus = "observed" | "ruleBased" | "manual";
export type JobStatus = "queued" | "running" | "completed" | "failed" | "expired";

export interface NormalizedTalents {
  normal: number;
  skill: number;
  burst: number;
}

export interface NormalizedWeapon {
  weaponId: string;
  level: number;
  ascension: number;
  refinement: number;
}

export interface NormalizedArtifactSet {
  setId: string;
  count: number;
}

export interface NormalizedArtifactStats {
  hpFlat?: number;
  hpPercent?: number;
  atkFlat?: number;
  atkPercent?: number;
  defFlat?: number;
  defPercent?: number;
  critRate?: number;
  critDamage?: number;
  energyRecharge?: number;
  elementalMastery?: number;
  anemoDamageBonus?: number;
  cryoDamageBonus?: number;
  dendroDamageBonus?: number;
  electroDamageBonus?: number;
  geoDamageBonus?: number;
  hydroDamageBonus?: number;
  pyroDamageBonus?: number;
  physicalDamageBonus?: number;
}

export interface SimulationBuildSnapshot {
  characterId: string;
  element: Element;
  rarity: 4 | 5;
  isOwned: boolean;
  level: number;
  ascension: number;
  constellation: number;
  talents?: NormalizedTalents;
  weapon?: NormalizedWeapon;
  artifacts?: {
    sets: NormalizedArtifactSet[];
    stats: NormalizedArtifactStats;
  };
  inputQuality: InputQuality;
  defaultedFields: string[];
}

export interface TeamRecommendationRequest {
  attackerId: string;
  mode: "spiralAbyss";
  half: "upper" | "lower";
  ownedOnly: boolean;
  enemy: "single" | "multiple";
  preference: "damage" | "stability" | "fourStar" | "built";
  characters: SimulationBuildSnapshot[];
}

export type CandidateSource = "aza" | "coOccurrence" | "ruleBased";

export interface TeamCandidate {
  attackerId: string;
  members: string[];
  sourceTypes: CandidateSource[];
  observedByAza: boolean;
  azaUsageRate: number;
  reactionType: string;
  hasSustain: boolean;
  energyStability: number;
  rotationConfidence: "high" | "medium" | "low";
}

export interface TeamRecommendation {
  members: string[];
  score: number;
  simulationStatus: SimulationStatus;
  sourceTypes: CandidateSource[];
  rotationConfidence: "high" | "medium" | "low";
  observedByAza: boolean;
  isCached: boolean;
  isStale: boolean;
  inputQuality: InputQuality;
  reasons: string[];
  alternatives: Record<string, string[]>;
}

export interface TeamRecommendationResult {
  attackerId: string;
  generatedAt: string;
  recommendations: TeamRecommendation[];
}

export interface TeamRecommendationJob {
  jobId: string;
  status: JobStatus;
  result?: TeamRecommendationResult;
  errorCode?: "invalidRequest" | "noCandidates" | "internalError";
}

export interface CandidateGenerationContext {
  request: TeamRecommendationRequest;
  abyssTeams: AbyssTeamStatistic[];
}
