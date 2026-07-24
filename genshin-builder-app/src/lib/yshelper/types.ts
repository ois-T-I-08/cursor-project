export const BATTLE_CONTENT_TYPES = ["abyss", "stygian"] as const;
export type BattleContentType = (typeof BATTLE_CONTENT_TYPES)[number];

export type BattleValidationState =
  | "valid"
  | "suspicious"
  | "invalid"
  | "stale";

export interface CanonicalSourceTeam {
  characters: string[];
  usageRate: number;
  usageCount?: number;
  rank?: number;
  side?: string;
  stageKey?: string;
  sampleSize?: number;
  metadata: Record<string, unknown>;
}

export interface CanonicalSourceCharacter {
  characterId: string;
  usageRate: number;
  usageCount?: number;
  rank?: number;
  side?: string;
  ownershipRate?: number;
  usageAmongOwnersRate?: number;
  sampleSize?: number;
}

export interface CanonicalSourcePayload {
  contractVersion: "canonical-v1";
  sourceVersion: string;
  seasonId: string;
  sourceUpdatedAt: string;
  rateUnit: "ratio" | "percent";
  sampleSize?: number;
  teams: CanonicalSourceTeam[];
  characters: CanonicalSourceCharacter[];
  metadata: Record<string, unknown>;
}

export interface NormalizedBattleTeam {
  teamKey: string;
  members: string[];
  usageRate: number;
  usageCount?: number;
  rank?: number;
  side?: string;
  stageKey?: string;
  sampleSize?: number;
  isResolved: boolean;
  sourceMetadata: Record<string, unknown>;
}

export interface NormalizedBattleCharacter {
  characterId: string;
  usageRate: number;
  usageCount?: number;
  rank?: number;
  side?: string;
  ownershipRate?: number;
  usageAmongOwnersRate?: number;
  sampleSize?: number;
  isResolved: boolean;
}

export interface NormalizedBattleStats {
  source: "YShelper";
  contentType: BattleContentType;
  schemaVersion: 1;
  sourceVersion: string;
  seasonId: string;
  sourceUpdatedAt: string;
  sampleSize?: number;
  metadata: Record<string, unknown>;
  teams: NormalizedBattleTeam[];
  characters: NormalizedBattleCharacter[];
}

export interface BattleValidationIssue {
  code:
    | "empty_payload"
    | "unknown_character"
    | "unknown_character_ratio"
    | "record_count_drop"
    | "usage_rate_shift";
  field: string;
  count?: number;
}

export interface BattleValidationResult {
  state: BattleValidationState;
  issues: BattleValidationIssue[];
  value: NormalizedBattleStats;
}

export interface YshelperAdapter {
  readonly name: string;
  adapt(
    contentType: BattleContentType,
    payload: Record<string, unknown>,
  ): NormalizedBattleStats;
}

export interface YshelperTransport {
  fetch(contentType: BattleContentType): Promise<Record<string, unknown>>;
}
