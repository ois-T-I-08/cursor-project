import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/amber/amber_api.dart';
import '../data/db/app_database.dart';
import '../data/models/master_models.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/character_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/sync/master_sync_service.dart';

const localUserIdKey = 'local_user_id';

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open();
  ref.onDispose(() => db.close());
  return db;
});

final amberApiProvider = Provider<AmberApi>((ref) {
  final api = AmberApi();
  ref.onDispose(api.dispose);
  return api;
});

final characterRepositoryProvider =
    FutureProvider<CharacterRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CharacterRepository(db);
});

final progressRepositoryProvider =
    FutureProvider<ProgressRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ProgressRepository(db);
});

final bookmarkRepositoryProvider =
    FutureProvider<BookmarkRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return BookmarkRepository(db);
});

final masterSyncServiceProvider =
    FutureProvider<MasterSyncService>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final amber = ref.watch(amberApiProvider);
  return MasterSyncService(amberApi: amber, db: db);
});

final charactersProvider = FutureProvider((ref) async {
  final repo = await ref.watch(characterRepositoryProvider.future);
  return repo.getAll();
});

/// 素材マスタのキャッシュ（詳細画面の名前解決用）
final materialsMapProvider = FutureProvider<Map<String, MasterMaterial>>((ref) async {
  final repo = await ref.watch(characterRepositoryProvider.future);
  return repo.getMaterialsMap();
});

final aggregatedBookmarksProvider = FutureProvider((ref) async {
  final repo = await ref.watch(bookmarkRepositoryProvider.future);
  return repo.getAggregated();
});

final lastSyncTimeProvider = FutureProvider<DateTime?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.getLastSyncTime();
});

/// ローカル匿名ユーザー ID（Web 版と同方針 — app_settings に永続化）
final localUserIdProvider = FutureProvider<String>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  var userId = await db.getSetting(localUserIdKey);
  if (userId == null || userId.isEmpty) {
    userId = const Uuid().v4();
    await db.setSetting(localUserIdKey, userId);
  }
  return userId;
});

final syncStateProvider =
    StateProvider<AsyncValue<SyncResult?>>((ref) => const AsyncValue.data(null));
