import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/daily_materials/daily_materials_service.dart';
import '../data/daily_materials/daily_progress_prefetch_service.dart';
import '../domain/daily_materials/daily_material_models.dart';
import 'app_providers.dart';
import 'hoyolab_game_providers.dart';

final dailyMaterialsServiceProvider =
    FutureProvider<DailyMaterialsService>((ref) async {
  final characters = await ref.watch(characterRepositoryProvider.future);
  final progress = await ref.watch(progressRepositoryProvider.future);
  final bookmarks = await ref.watch(bookmarkRepositoryProvider.future);
  return DailyMaterialsService(
    scheduleRepository: ref.watch(dailyMaterialScheduleRepositoryProvider),
    characterRepository: characters,
    progressRepository: progress,
    bookmarkRepository: bookmarks,
  );
});

/// 曜日別素材プラン（family: ISO weekday 1–7）
final dailyMaterialsPlanProvider =
    FutureProvider.family<DailyMaterialsPlan, int>((ref, weekday) async {
  final userId = await ref.watch(localUserIdProvider.future);
  final service = await ref.watch(dailyMaterialsServiceProvider.future);
  final ownedMap = await ref.watch(hoyolabOwnedCharacterMapProvider.future);
  return service.buildPlan(
    userId: userId,
    weekday: weekday,
    ownedCharacterIds: ownedMap.keys.toSet(),
  );
});

final dailyProgressPrefetchServiceProvider =
    FutureProvider<DailyProgressPrefetchService>((ref) async {
  final characters = await ref.watch(characterRepositoryProvider.future);
  final progress = await ref.watch(progressRepositoryProvider.future);
  final hoyolab = await ref.watch(hoyolabGameDataRepositoryProvider.future);
  return DailyProgressPrefetchService(
    scheduleRepository: ref.watch(dailyMaterialScheduleRepositoryProvider),
    characterRepository: characters,
    progressRepository: progress,
    hoyolabRepository: hoyolab,
  );
});

/// ホーム起動時に一度走らせる。今日必要な所持キャラの Progress を用意する。
final dailyProgressPrefetchProvider =
    FutureProvider<DailyProgressPrefetchResult>((ref) async {
  final userId = await ref.watch(localUserIdProvider.future);
  final ownedMap = await ref.watch(hoyolabOwnedCharacterMapProvider.future);
  final service = await ref.watch(dailyProgressPrefetchServiceProvider.future);
  final result = await service.prefetchForToday(
    userId: userId,
    ownedCharacterIds: ownedMap.keys.toSet(),
  );
  if (result.createdOrEnsured > 0 || result.syncedFromHoyolab > 0) {
    ref.invalidate(dailyMaterialsPlanProvider);
  }
  return result;
});

void invalidateDailyMaterialsProviders(WidgetRef ref) {
  ref.invalidate(dailyMaterialsServiceProvider);
  ref.invalidate(dailyMaterialsPlanProvider);
  ref.invalidate(dailyProgressPrefetchProvider);
}
