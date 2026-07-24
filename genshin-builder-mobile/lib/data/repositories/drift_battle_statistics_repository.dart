import '../../domain/battle_statistics/battle_statistics.dart';
import '../../domain/repositories/battle_statistics_repository.dart';
import '../db/app_database.dart';

class DriftBattleStatisticsRepository implements BattleStatisticsRepository {
  DriftBattleStatisticsRepository(this._db);

  static const _etagSettingKey = 'remote_battle_stats_manifest_etag';

  final AppDatabase _db;

  @override
  Future<BattleStatsManifestItem?> readManifest(
    BattleStatsContentType contentType,
  ) => _db.getRemoteBattleManifest(contentType);

  @override
  Future<String?> readManifestEtag() => _db.getSetting(_etagSettingKey);

  @override
  Future<void> writeManifestEtag(String etag) =>
      _db.setSetting(_etagSettingKey, etag);

  @override
  Future<void> replaceBundle(BattleStatsBundle bundle) =>
      _db.replaceRemoteBattleBundle(bundle);

  @override
  Future<List<RemoteBattleTeam>> readTeams(
    BattleStatsContentType contentType,
  ) => _db.getRemoteBattleTeams(contentType);

  @override
  Future<void> recordSyncState(
    BattleStatsContentType contentType,
    RemoteBattleStatsState state, {
    String? errorCode,
  }) =>
      _db.recordRemoteBattleSyncState(contentType, state, errorCode: errorCode);
}
