import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/battle_statistics/sync_battle_statistics.dart';
import '../data/battle_statistics/backend_battle_statistics_api.dart';
import '../data/battle_statistics/battle_stats_payload_hash.dart';
import '../data/repositories/drift_battle_statistics_repository.dart';
import '../domain/repositories/battle_statistics_repository.dart';
import 'app_providers.dart';

const _battleStatisticsBaseUrl = String.fromEnvironment(
  'GENSHIN_BUILDER_API_BASE_URL',
  defaultValue: '',
);

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
