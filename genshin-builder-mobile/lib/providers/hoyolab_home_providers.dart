import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hoyolab/hoyolab_constants.dart';
import '../data/hoyolab/hoyolab_home_disk_cache.dart';
import '../data/hoyolab/models/daily_note.dart';
import '../data/hoyolab/models/game_record.dart';
import 'app_providers.dart';
import 'hoyolab_game_providers.dart';
import 'hoyolab_providers.dart';

final hoyolabHomeDiskCacheProvider =
    FutureProvider<HoyolabHomeDiskCache>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return HoyolabHomeDiskCache(AppDatabaseSettingsStore(db));
});

final dailyNoteProvider =
    AsyncNotifierProvider<DailyNoteNotifier, DailyNote?>(DailyNoteNotifier.new);

class DailyNoteNotifier extends AsyncNotifier<DailyNote?> {
  @override
  Future<DailyNote?> build() => _load(forceRefresh: false);

  Future<void> refresh() async {
    state = const AsyncLoading<DailyNote?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<DailyNote?> _load({required bool forceRefresh}) async {
    final flags = await ref.read(featureFlagsProvider.future);
    if (!flags.hoyolabLinkEnabled) return null;

    final session = await ref.read(hoyolabSessionProvider.future);
    if (!session.canFetchDailyNote) return null;

    final uid = session.uid!;
    final diskCache = await ref.read(hoyolabHomeDiskCacheProvider.future);

    if (!forceRefresh) {
      final cached = await diskCache.readDailyNote(uid);
      if (cached != null) {
        unawaited(_refreshInBackground(uid));
        return cached.data;
      }
    }

    return _fetchAndSave(uid);
  }

  Future<void> _refreshInBackground(String uid) async {
    try {
      final fresh = await _fetchAndSave(uid);
      state = AsyncData(fresh);
    } catch (_) {
      // キャッシュ表示中はエラーで上書きしない
    }
  }

  Future<DailyNote?> _fetchAndSave(String uid) async {
    final repo = await ref.read(hoyolabRepositoryProvider.future);
    final note = await repo.fetchDailyNote();
    final diskCache = await ref.read(hoyolabHomeDiskCacheProvider.future);
    await diskCache.saveDailyNote(uid, note);
    return note;
  }
}

final hoyolabAdventureStatusProvider = AsyncNotifierProvider<
    AdventureStatusNotifier, AdventureStatus?>(AdventureStatusNotifier.new);

class AdventureStatusNotifier extends AsyncNotifier<AdventureStatus?> {
  @override
  Future<AdventureStatus?> build() => _load(forceRefresh: false);

  Future<void> refresh() async {
    state = const AsyncLoading<AdventureStatus?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  Future<AdventureStatus?> _load({required bool forceRefresh}) async {
    final flags = await ref.read(featureFlagsProvider.future);
    if (!flags.hoyolabLinkEnabled) return null;

    final session = await ref.read(hoyolabSessionProvider.future);
    if (!session.isLinked) return null;

    final uid = session.uid!;
    final diskCache = await ref.read(hoyolabHomeDiskCacheProvider.future);
    final memoryCache = ref.read(hoyolabGameDataCacheProvider);

    if (!forceRefresh) {
      final memory = memoryCache.getAdventure<AdventureStatus>(
        HoyolabConstants.adventureStatusCacheTtl,
      );
      if (memory != null) return memory;

      final cached = await diskCache.readAdventure(uid);
      if (cached != null) {
        memoryCache.setAdventure(cached.data);
        if (!cached.isFresh(HoyolabConstants.adventureStatusCacheTtl)) {
          unawaited(_refreshInBackground(uid, delayed: true));
        }
        return cached.data;
      }
    }

    return _fetchAndSave(uid);
  }

  Future<void> _refreshInBackground(
    String uid, {
    bool delayed = false,
  }) async {
    if (delayed) {
      await Future<void>.delayed(HoyolabConstants.adventureStatusRefreshDelay);
    }
    try {
      final fresh = await _fetchAndSave(uid);
      state = AsyncData(fresh);
    } catch (_) {
      // キャッシュ表示中はエラーで上書きしない
    }
  }

  Future<AdventureStatus?> _fetchAndSave(String uid) async {
    final repo = await ref.read(hoyolabGameDataRepositoryProvider.future);
    final status = await repo.fetchAdventureStatus(forceRefresh: true);
    if (status == null) return null;

    final diskCache = await ref.read(hoyolabHomeDiskCacheProvider.future);
    await diskCache.saveAdventure(uid, status);
    return status;
  }
}

/// アプリ起動直後にリアルタイムメモ取得を開始する（冒険状況は遅延読み込み）
void prefetchHoyolabHomeData(WidgetRef ref) {
  unawaited(ref.read(dailyNoteProvider.future));
}
