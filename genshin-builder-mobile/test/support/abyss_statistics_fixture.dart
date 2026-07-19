import 'package:genshin_builder_mobile/domain/abyss/abyss_statistics.dart';

AbyssStatistics sampleAbyssStatistics({
  bool isStale = false,
  List<AbyssCharacterStatistic>? characters,
  List<AbyssTeamStatistic>? teams,
}) {
  return AbyssStatistics(
    version: AbyssVersion(
      scheduleId: 106,
      periodStart: DateTime.utc(2026, 7, 16),
      periodEnd: DateTime.utc(2026, 8, 1),
      sourceApiVersion: '1.4.0',
    ),
    metadata: AbyssStatisticsMetadata(
      source: AbyssDataSource.aza,
      fetchedAt: DateTime.utc(2026, 7, 19, 1, 30),
      expiresAt: DateTime.utc(2026, 7, 19, 7, 30),
      sourceUpdatedAt: DateTime.utc(2026, 7, 19),
      isStale: isStale,
      sampleSize: 42,
      referenceSampleSize: 84,
      collectionProgress: 0.5,
      warningCode: isStale ? AbyssStatisticsFailure.staleCache : null,
      upstreamErrorCode: isStale ? AbyssStatisticsFailure.timeout : null,
    ),
    characters:
        characters ??
        const [
          AbyssCharacterStatistic(
            characterId: '10000052',
            characterName: '雷電将軍',
            usageRate: 0.876,
            ownershipRate: 0.8,
            usageAmongOwnersRate: 0.75,
            upperHalfRate: 0.4,
            lowerHalfRate: 0.6,
            constellationRates: [
              AbyssConstellationStatistic(constellation: 0, rate: 0.5),
            ],
            weapons: [
              AbyssRateStatistic(
                id: '13509',
                usageRate: 0.4,
                displayName: '草薙の稲光',
              ),
            ],
            artifacts: [
              AbyssArtifactStatistic(
                setPieces: [
                  AbyssArtifactSetPiece(artifactSetId: '15020', pieces: 4),
                ],
                usageRate: 0.7,
              ),
            ],
          ),
        ],
    teams:
        teams ??
        const [
          AbyssTeamStatistic(
            half: AbyssTeamHalf.upper,
            members: [
              AbyssTeamMember(characterId: '10000052', characterName: '雷電将軍'),
              AbyssTeamMember(characterId: '10000023'),
              AbyssTeamMember(characterId: '10000054'),
              AbyssTeamMember(characterId: '10000032'),
            ],
            usageRate: 0.3,
            ownershipRate: 0.2,
            usageAmongOwnersRate: 0.25,
          ),
        ],
  );
}
