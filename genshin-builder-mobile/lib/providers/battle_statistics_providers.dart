import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/battle_statistics/sync_battle_statistics.dart';
import '../data/battle_statistics/backend_battle_statistics_api.dart';
import '../data/battle_statistics/battle_stats_payload_hash.dart';
import '../data/repositories/drift_battle_statistics_repository.dart';
import '../domain/battle_statistics/battle_statistics.dart';
import '../domain/repositories/battle_statistics_repository.dart';
import 'app_providers.dart';

const _battleStatisticsBaseUrl = String.fromEnvironment(
  'GENSHIN_BUILDER_API_BASE_URL',
  defaultValue: '',
);

/// Local browse model for the YShelper battle-statistics screen.
class BattleStatisticsBrowsePage {
  const BattleStatisticsBrowsePage({
    required this.contentType,
    required this.seasonId,
    required this.sourceUpdatedAt,
    required this.syncedAt,
    required this.teams,
    required this.characters,
    required this.isStale,
    required this.isOffline,
    this.sampleSize,
  });

  final BattleStatsContentType contentType;
  final String seasonId;
  final DateTime sourceUpdatedAt;
  final DateTime syncedAt;
  final List<RemoteBattleTeam> teams;
  final List<RemoteBattleCharacterUsage> characters;
  final int? sampleSize;
  final bool isStale;
  final bool isOffline;
}

class BattleStatisticsBrowseState {
  const BattleStatisticsBrowseState({
    required this.enabled,
    this.abyss,
    this.stygian,
  });

  final bool enabled;
  final BattleStatisticsBrowsePage? abyss;
  final BattleStatisticsBrowsePage? stygian;
}

final battleStatisticsSyncEnabledProvider = Provider<bool>(
  (_) => _battleStatisticsBaseUrl.trim().isNotEmpty,
);

final backendBattleStatisticsApiProvider = Provider<BackendBattleStatisticsApi>(
  (ref) {
    final api = BackendBattleStatisticsApi(baseUrl: _battleStatisticsBaseUrl);
    ref.onDispose(api.dispose);
    return api;
  },
);

final battleStatisticsRepositoryProvider =
    FutureProvider<BattleStatisticsRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      return DriftBattleStatisticsRepository(db);
    });

final syncBattleStatisticsUseCaseProvider =
    FutureProvider<SyncBattleStatisticsUseCase>((ref) async {
      return SyncBattleStatisticsUseCase(
        remote: ref.watch(backendBattleStatisticsApiProvider),
        repository: await ref.watch(battleStatisticsRepositoryProvider.future),
        characterRepository: await ref.watch(
          characterRepositoryProvider.future,
        ),
        integrityVerifier: const Sha256BattleStatsIntegrityVerifier(),
      );
    });

final battleStatisticsStartupSyncProvider =
    FutureProvider<BattleStatisticsSyncResult>((ref) async {
      final useCase = await ref.watch(
        syncBattleStatisticsUseCaseProvider.future,
      );
      return useCase.execute();
    });

final battleStatisticsBrowseProvider =
    FutureProvider<BattleStatisticsBrowseState>((ref) async {
      final enabled = ref.watch(battleStatisticsSyncEnabledProvider);
      if (!enabled) {
        return const BattleStatisticsBrowseState(enabled: false);
      }
      final repo = await ref.watch(battleStatisticsRepositoryProvider.future);
      var offline = false;
      try {
        await ref.watch(battleStatisticsStartupSyncProvider.future);
      } catch (_) {
        offline = true;
      }

      Future<BattleStatisticsBrowsePage?> load(
        BattleStatsContentType contentType,
      ) async {
        final manifest = await repo.readManifest(contentType);
        final syncedAt = await repo.readSyncedAt(contentType);
        if (manifest == null || syncedAt == null) return null;
        final teams = await repo.readTeams(contentType);
        final characters = await repo.readCharacters(contentType);
        final sampleSize =
            characters
                .map((item) => item.sampleSize)
                .whereType<int>()
                .fold<int?>(null, (max, value) {
                  if (max == null || value > max) return value;
                  return max;
                }) ??
            teams
                .map((item) => item.sampleSize)
                .whereType<int>()
                .fold<int?>(null, (max, value) {
                  if (max == null || value > max) return value;
                  return max;
                });
        final age = DateTime.now().difference(syncedAt);
        return BattleStatisticsBrowsePage(
          contentType: contentType,
          seasonId: manifest.seasonId,
          sourceUpdatedAt: manifest.updatedAt,
          syncedAt: syncedAt,
          teams: teams,
          characters: characters,
          sampleSize: sampleSize,
          isStale: age > const Duration(days: 14),
          isOffline: offline,
        );
      }

      return BattleStatisticsBrowseState(
        enabled: true,
        abyss: await load(BattleStatsContentType.abyss),
        stygian: await load(BattleStatsContentType.stygian),
      );
    });
