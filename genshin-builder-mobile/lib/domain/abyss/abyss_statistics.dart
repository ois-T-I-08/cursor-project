enum AbyssDataSource {
  aza;

  String get displayName => switch (this) {
    AbyssDataSource.aza => 'AZA.GG',
  };
}

enum AbyssStatisticsFailure {
  networkError,
  timeout,
  rateLimited,
  invalidResponse,
  notConfigured,
  featureDisabled,
  noData,
  staleCache,
  unknownError,
}

class AbyssStatisticsException implements Exception {
  const AbyssStatisticsException(this.failure);

  final AbyssStatisticsFailure failure;

  @override
  String toString() => 'AbyssStatisticsException(${failure.name})';
}

class AbyssVersion {
  const AbyssVersion({
    required this.scheduleId,
    required this.periodStart,
    required this.periodEnd,
    required this.sourceApiVersion,
  });

  final int scheduleId;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// AZA.GG APIの仕様版。原神のゲームバージョンではない。
  final String sourceApiVersion;
}

class AbyssStatisticsMetadata {
  const AbyssStatisticsMetadata({
    required this.source,
    required this.fetchedAt,
    required this.expiresAt,
    required this.sourceUpdatedAt,
    required this.isStale,
    required this.sampleSize,
    required this.referenceSampleSize,
    required this.collectionProgress,
    this.warningCode,
    this.upstreamErrorCode,
  });

  final AbyssDataSource source;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final DateTime sourceUpdatedAt;
  final bool isStale;
  final int sampleSize;
  final int referenceSampleSize;
  final double collectionProgress;
  final AbyssStatisticsFailure? warningCode;
  final AbyssStatisticsFailure? upstreamErrorCode;
}

class AbyssRateStatistic {
  const AbyssRateStatistic({
    required this.id,
    required this.usageRate,
    this.displayName,
  });

  final String id;
  final double usageRate;
  final String? displayName;

  AbyssRateStatistic copyWith({String? displayName}) => AbyssRateStatistic(
    id: id,
    usageRate: usageRate,
    displayName: displayName ?? this.displayName,
  );
}

class AbyssArtifactSetPiece {
  const AbyssArtifactSetPiece({
    required this.artifactSetId,
    required this.pieces,
  });

  final String artifactSetId;
  final int pieces;
}

class AbyssArtifactStatistic {
  const AbyssArtifactStatistic({
    required this.setPieces,
    required this.usageRate,
  });

  final List<AbyssArtifactSetPiece> setPieces;
  final double usageRate;
}

class AbyssConstellationStatistic {
  const AbyssConstellationStatistic({
    required this.constellation,
    required this.rate,
  });

  final int constellation;
  final double rate;
}

class AbyssCharacterStatistic {
  const AbyssCharacterStatistic({
    required this.characterId,
    required this.usageRate,
    required this.ownershipRate,
    required this.usageAmongOwnersRate,
    required this.upperHalfRate,
    required this.lowerHalfRate,
    required this.constellationRates,
    required this.weapons,
    required this.artifacts,
    this.characterName,
    this.iconUrl,
  });

  final String characterId;
  final String? characterName;
  final String? iconUrl;
  final double usageRate;
  final double ownershipRate;
  final double usageAmongOwnersRate;
  final double? upperHalfRate;
  final double? lowerHalfRate;
  final List<AbyssConstellationStatistic> constellationRates;
  final List<AbyssRateStatistic> weapons;
  final List<AbyssArtifactStatistic> artifacts;

  AbyssCharacterStatistic copyWith({
    String? characterName,
    String? iconUrl,
    List<AbyssRateStatistic>? weapons,
  }) => AbyssCharacterStatistic(
    characterId: characterId,
    characterName: characterName ?? this.characterName,
    iconUrl: iconUrl ?? this.iconUrl,
    usageRate: usageRate,
    ownershipRate: ownershipRate,
    usageAmongOwnersRate: usageAmongOwnersRate,
    upperHalfRate: upperHalfRate,
    lowerHalfRate: lowerHalfRate,
    constellationRates: constellationRates,
    weapons: weapons ?? this.weapons,
    artifacts: artifacts,
  );
}

enum AbyssTeamHalf { upper, lower }

class AbyssTeamMember {
  const AbyssTeamMember({
    required this.characterId,
    this.characterName,
    this.iconUrl,
  });

  final String characterId;
  final String? characterName;
  final String? iconUrl;

  AbyssTeamMember copyWith({String? characterName, String? iconUrl}) =>
      AbyssTeamMember(
        characterId: characterId,
        characterName: characterName ?? this.characterName,
        iconUrl: iconUrl ?? this.iconUrl,
      );
}

class AbyssTeamStatistic {
  const AbyssTeamStatistic({
    required this.half,
    required this.members,
    required this.usageRate,
    required this.ownershipRate,
    required this.usageAmongOwnersRate,
  });

  final AbyssTeamHalf half;
  final List<AbyssTeamMember> members;
  final double usageRate;
  final double ownershipRate;
  final double usageAmongOwnersRate;

  AbyssTeamStatistic copyWith({List<AbyssTeamMember>? members}) =>
      AbyssTeamStatistic(
        half: half,
        members: members ?? this.members,
        usageRate: usageRate,
        ownershipRate: ownershipRate,
        usageAmongOwnersRate: usageAmongOwnersRate,
      );
}

class AbyssStatistics {
  const AbyssStatistics({
    required this.version,
    required this.metadata,
    required this.characters,
    required this.teams,
  });

  final AbyssVersion version;
  final AbyssStatisticsMetadata metadata;
  final List<AbyssCharacterStatistic> characters;
  final List<AbyssTeamStatistic> teams;

  bool get isEmpty => characters.isEmpty && teams.isEmpty;

  AbyssStatistics copyWith({
    List<AbyssCharacterStatistic>? characters,
    List<AbyssTeamStatistic>? teams,
  }) => AbyssStatistics(
    version: version,
    metadata: metadata,
    characters: characters ?? this.characters,
    teams: teams ?? this.teams,
  );
}
