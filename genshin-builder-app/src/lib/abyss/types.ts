export type AbyssStatisticsErrorCode =
  | "networkError"
  | "timeout"
  | "rateLimited"
  | "invalidResponse"
  | "notConfigured"
  | "featureDisabled"
  | "noData"
  | "staleCache"
  | "unknownError";

export interface AbyssVersion {
  scheduleId: number;
  periodStart: string;
  periodEnd: string;
  sourceApiVersion: string;
}

export interface AbyssStatisticsMetadata {
  source: "AZA.GG";
  fetchedAt: string;
  expiresAt: string;
  sourceUpdatedAt: string;
  isStale: boolean;
  warningCode?: "staleCache";
  upstreamErrorCode?: Exclude<AbyssStatisticsErrorCode, "staleCache">;
  sampleSize: number;
  referenceSampleSize: number;
  collectionProgress: number;
}

export interface AbyssRateStatistic {
  id: string;
  usageRate: number;
}

export interface AbyssArtifactStatistic {
  setPieces: Array<{
    artifactSetId: string;
    pieces: number;
  }>;
  usageRate: number;
}

export interface AbyssConstellationStatistic {
  constellation: number;
  rate: number;
}

export interface AbyssCharacterStatistic {
  characterId: string;
  usageRate: number;
  ownershipRate: number;
  usageAmongOwnersRate: number;
  upperHalfRate: number | null;
  lowerHalfRate: number | null;
  constellationRates: AbyssConstellationStatistic[];
  weapons: AbyssRateStatistic[];
  artifacts: AbyssArtifactStatistic[];
}

export interface AbyssTeamStatistic {
  half: "upper" | "lower";
  members: string[];
  usageRate: number;
  ownershipRate: number;
  usageAmongOwnersRate: number;
}

export interface AbyssStatistics {
  version: AbyssVersion;
  metadata: AbyssStatisticsMetadata;
  characters: AbyssCharacterStatistic[];
  teams: AbyssTeamStatistic[];
}

export type AbyssStatisticsSnapshot = Omit<AbyssStatistics, "metadata"> & {
  metadata: Omit<
    AbyssStatisticsMetadata,
    | "fetchedAt"
    | "expiresAt"
    | "isStale"
    | "warningCode"
    | "upstreamErrorCode"
  >;
};
