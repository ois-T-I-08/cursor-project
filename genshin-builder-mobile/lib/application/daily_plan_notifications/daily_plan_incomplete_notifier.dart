import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../hoyolab_reminders/notification_bootstrap.dart';
import 'daily_plan_notification_ids.dart';

/// Displays P1-8C incomplete notifications (no scheduling).
class DailyPlanIncompleteNotifier {
  const DailyPlanIncompleteNotifier();

  Future<void> showIncomplete({required int incompleteCount}) async {
    await NotificationBootstrap.ensureInitializedOrThrow();
    const title = DailyPlanNotificationIds.incompleteTitle;
    final body = DailyPlanNotificationIds.incompleteBody(incompleteCount);
    await NotificationBootstrap.plugin.show(
      DailyPlanNotificationIds.incomplete,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          DailyPlanNotificationIds.incompleteChannelId,
          DailyPlanNotificationIds.incompleteChannelName,
          channelDescription:
              DailyPlanNotificationIds.incompleteChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: DailyPlanNotificationIds.incompletePayload,
    );
  }

  Future<void> cancel() async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      await NotificationBootstrap.plugin
          .cancel(DailyPlanNotificationIds.incomplete);
    } catch (_) {
      debugPrint('daily_plan_incomplete: cancel notification failed');
    }
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      if (kIsWeb) return false;
      if (defaultTargetPlatform != TargetPlatform.android) return false;
      final android = NotificationBootstrap.plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }
}
