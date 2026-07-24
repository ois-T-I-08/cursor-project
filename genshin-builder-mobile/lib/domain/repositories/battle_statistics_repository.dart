import '../battle_statistics/battle_statistics.dart';

abstract class BattleStatisticsRepository {
  Future<BattleStatsManifestItem?> readManifest(
    BattleStatsContentType contentType,
  );

  Future<String?> readManifestEtag();

  Future<void> writeManifestEtag(String etag);

  Future<void> replaceBundle(BattleStatsBundle bundle);

  Future<List<RemoteBattleTeam>> readTeams(BattleStatsContentType contentType);

  Future<void> recordSyncState(
    BattleStatsContentType contentType,
    RemoteBattleStatsState state, {
    String? errorCode,
  });
}

abstract class BattleStatisticsRemoteSource {
  Future<BattleStatsManifestFetchResult> fetchManifest({String? etag});

  Future<BattleStatsBundlePage> fetchBundlePage({
    required BattleStatsContentType contentType,
    required int revision,
    required int page,
  });
}

abstract class BattleStatsIntegrityVerifier {
  bool matches(BattleStatsBundle bundle);
}

class BattleStatsManifestFetchResult {
  const BattleStatsManifestFetchResult({
    required this.notModified,
    this.manifest,
  });

  final bool notModified;
  final BattleStatsManifest? manifest;
}

class BattleStatsBundlePage {
  const BattleStatsBundlePage({
    required this.schemaVersion,
    required this.contentType,
    required this.sourceVersion,
    required this.seasonId,
    required this.revision,
    required this.payloadHash,
    required this.sourceUpdatedAt,
    required this.page,
    required this.pageCount,
    required this.teams,
    required this.characters,
    this.sampleSize,
  });

  final int schemaVersion;
  final BattleStatsContentType contentType;
  final String sourceVersion;
  final String seasonId;
  final int revision;
  final String payloadHash;
  final DateTime sourceUpdatedAt;
  final int? sampleSize;
  final int page;
  final int pageCount;
  final List<RemoteBattleTeam> teams;
  final List<RemoteBattleCharacterUsage> characters;
}
