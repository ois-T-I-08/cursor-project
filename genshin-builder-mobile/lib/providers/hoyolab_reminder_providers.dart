import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/hoyolab_reminders/notification_schedule_coordinator.dart';
import '../application/hoyolab_reminders/notification_scheduler.dart';
import '../application/hoyolab_reminders/reminder_settings_store.dart';
import '../data/hoyolab/hoyolab_home_disk_cache.dart';
import 'app_providers.dart';

final reminderSettingsStoreProvider =
    FutureProvider<ReminderSettingsStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ReminderSettingsStore(AppDatabaseSettingsStore(db));
});

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return const FlutterNotificationScheduler();
});

final notificationScheduleCoordinatorProvider =
    FutureProvider<NotificationScheduleCoordinator>((ref) async {
  final settings = await ref.watch(reminderSettingsStoreProvider.future);
  final scheduler = ref.watch(notificationSchedulerProvider);
  return NotificationScheduleCoordinator(
    settings: settings,
    scheduler: scheduler,
  );
});
