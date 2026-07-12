import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/background_master_repair.dart';
import '../data/sync/icon_preload_service.dart';
import '../data/sync/master_sync_service.dart';
import 'app_providers.dart';
import 'daily_materials_providers.dart';

/// ホーム後修復ゲート（autoDispose にしない — 同一プロセスで冪等）
final backgroundMasterRepairProvider = Provider<BackgroundMasterRepair>((ref) {
  return BackgroundMasterRepair(
    loadSyncStatus: () async {
      final db = await ref.read(appDatabaseProvider.future);
      return db.getSyncStatus();
    },
    runProbe: () async {
      final probe = await ref.read(masterContentProbeProvider.future);
      return probe.check();
    },
    runMasterSync: () async {
      final db = await ref.read(appDatabaseProvider.future);
      final amber = ref.read(amberApiProvider);
      final result = await MasterSyncService(
        amberApi: amber,
        db: db,
      ).syncMasterData();
      final versioning = await ref.read(versioningServiceProvider.future);
      await versioning.updateAndPersistVersions();
      ref.invalidate(charactersProvider);
      ref.invalidate(syncStatusProvider);
      ref.invalidate(lastSyncTimeProvider);
      ref.invalidate(aggregatedBookmarksProvider);
      ref.invalidate(materialsMapProvider);
      ref.invalidate(versionStatusProvider);
      ref.invalidate(dailyMaterialScheduleRepositoryProvider);
      ref.invalidate(dailyMaterialsServiceProvider);
      ref.invalidate(dailyMaterialsPlanProvider);
      ref.invalidate(dailyProgressPrefetchProvider);
      return result;
    },
    preloadIcons: () async {
      final db = await ref.read(appDatabaseProvider.future);
      return IconPreloadService(db).preloadMasterIcons(onlyMissing: true);
    },
    backfillWeights: () async {
      final db = await ref.read(appDatabaseProvider.future);
      final weightRepo = ref.read(artifactScoreWeightRepositoryProvider);
      final characters = await db.getAllCharacters();
      final missingWeightIds =
          await weightRepo.syncMissingCharacterProfiles(characters);
      if (missingWeightIds.isNotEmpty) {
        await db.insertSyncLog(
          'partial',
          'artifact score weights missing for: ${missingWeightIds.join(',')}',
        );
      }
    },
  );
});
