import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../providers/daily_materials_providers.dart';
import '../models/sync_status.dart';
import 'icon_preload_service.dart';
import 'master_sync_service.dart';

/// マスタ同期本体 + versioning + 必須 invalidate（アイコン・weights は含まない）
Future<SyncResult> runMasterDataSync(
  WidgetRef ref, {
  void Function(SyncProgress progress)? onProgress,
  bool fullUpgrade = false,
}) async {
  final db = await ref.read(appDatabaseProvider.future);
  final amber = ref.read(amberApiProvider);
  final service = MasterSyncService(
    amberApi: amber,
    db: db,
    fullUpgrade: fullUpgrade,
  );
  final result = await service.syncMasterData(onProgress: onProgress);

  final versioning = await ref.read(versioningServiceProvider.future);
  await versioning.updateAndPersistVersions();

  invalidateMasterDataProviders(ref);
  invalidateDailyMaterialsProviders(ref);
  return result;
}

/// アイコンをディスクキャッシュへ事前取得（失敗は呼び出し側で無視してよい）
Future<int> preloadMasterIconsForRef(
  WidgetRef ref, {
  void Function(SyncProgress progress)? onProgress,
  bool onlyMissing = true,
}) async {
  final db = await ref.read(appDatabaseProvider.future);
  onProgress?.call(
    const SyncProgress(
      phase: SyncPhase.iconPreload,
      current: 0,
      total: 0,
      detail: '準備中',
    ),
  );
  return IconPreloadService(db).preloadMasterIcons(
    onlyMissing: onlyMissing,
    onProgress: onProgress,
  );
}

/// Remote score weights の欠落補完（失敗してもマスタ同期成功を覆さない）
Future<void> syncMissingScoreWeightsForRef(WidgetRef ref) async {
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
}

/// 設定画面用: マスタ同期のあとアイコン（と weights）まで await
Future<({SyncResult result, int iconsLoaded})> runMasterSyncWithIconPreload(
  WidgetRef ref, {
  void Function(SyncProgress progress)? onProgress,
  bool preloadOnlyMissingIcons = false,
  bool fullUpgrade = false,
}) async {
  final result = await runMasterDataSync(
    ref,
    onProgress: onProgress,
    fullUpgrade: fullUpgrade,
  );

  var iconsLoaded = 0;
  try {
    iconsLoaded = await preloadMasterIconsForRef(
      ref,
      onProgress: onProgress,
      onlyMissing: preloadOnlyMissingIcons,
    );
  } catch (_) {
    // アイコン失敗はマスタ同期成功を失敗扱いにしない
  }

  try {
    await syncMissingScoreWeightsForRef(ref);
  } catch (_) {
    // weights 失敗もマスタ成功を覆さない
  }

  return (result: result, iconsLoaded: iconsLoaded);
}
