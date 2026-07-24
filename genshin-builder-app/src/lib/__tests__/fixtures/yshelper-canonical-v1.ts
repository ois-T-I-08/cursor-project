export function yshelperCanonicalFixture(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    contractVersion: "canonical-v1",
    sourceVersion: "fixture-1",
    seasonId: "2026-07",
    sourceUpdatedAt: "2026-07-24T00:00:00.000Z",
    rateUnit: "ratio",
    sampleSize: 1_000,
    metadata: {},
    teams: [
      {
        characters: ["10000001", "10000002", "10000003", "10000004"],
        usageRate: 0.25,
        usageCount: 250,
        rank: 1,
        side: "upper",
        stageKey: "12-1",
        sampleSize: 1_000,
        metadata: {},
      },
    ],
    characters: [
      {
        characterId: "10000001",
        usageRate: 0.5,
        usageCount: 500,
        rank: 1,
        side: "upper",
        ownershipRate: 0.8,
        usageAmongOwnersRate: 0.625,
        sampleSize: 1_000,
      },
    ],
    ...overrides,
  };
}
