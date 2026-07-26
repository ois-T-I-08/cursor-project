import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/daily_plan_notifications/daily_plan_incomplete_notifier.dart';
import '../application/daily_plan_notifications/daily_plan_incomplete_scheduler.dart';
import '../application/daily_plan_notifications/daily_plan_notification_coordinator.dart';
import '../application/daily_plan_notifications/daily_plan_notification_settings_store.dart';
import '../data/hoyolab/hoyolab_home_disk_cache.dart';
import 'app_providers.dart';
import 'daily_plan_completion_providers.dart';

final dailyPlanNotificationSettingsStoreProvider =
    FutureProvider<DailyPlanNotificationSettingsStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DailyPlanNotificationSettingsStore(AppDatabaseSettingsStore(db));
});

final dailyPlanIncompleteSchedulerProvider =
    Provider<DailyPlanIncompleteScheduler>((ref) {
  return DailyPlanIncompleteScheduler();
});

final dailyPlanIncompleteNotifierProvider =
    Provider<DailyPlanIncompleteNotifier>((ref) {
  return const DailyPlanIncompleteNotifier();
});

final dailyPlanNotificationCoordinatorProvider =
    FutureProvider<DailyPlanNotificationCoordinator>((ref) async {
  final settings =
      await ref.watch(dailyPlanNotificationSettingsStoreProvider.future);
  final evalHistory = await ref.watch(dailyPlanEvalHistoryRepoProvider.future);
  final scheduler = ref.watch(dailyPlanIncompleteSchedulerProvider);
  return DailyPlanNotificationCoordinator(
    settings: settings,
    evalHistory: evalHistory,
    scheduler: scheduler,
  );
});

final dailyPlanIncompleteEnabledProvider = FutureProvider<bool>((ref) async {
  final store =
      await ref.watch(dailyPlanNotificationSettingsStoreProvider.future);
  return store.isIncompleteEnabled();
});
