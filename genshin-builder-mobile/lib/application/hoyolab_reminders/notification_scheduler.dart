import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_bootstrap.dart';
import 'reminder_models.dart';

abstract class NotificationScheduler {
  Future<bool> areNotificationsEnabled();

  /// Android 13+: request POST_NOTIFICATIONS. Other platforms: no-op true/false.
  Future<bool> requestPermission();

  Future<void> show({
    required ReminderKind kind,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> schedule({
    required ReminderKind kind,
    required DateTime notifyAt,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> cancel(ReminderKind kind);

  Future<void> cancelAllReminders();
}

class FlutterNotificationScheduler implements NotificationScheduler {
  const FlutterNotificationScheduler();

  static const _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;

  @override
  Future<bool> areNotificationsEnabled() async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      if (kIsWeb) return false;
      if (defaultTargetPlatform != TargetPlatform.android) {
        // P1-8B targets Android; treat other OS as not enabled for scheduling.
        return false;
      }
      final android = NotificationBootstrap.plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      debugPrint('notifications: areNotificationsEnabled failed');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return false;
      }
      final android = NotificationBootstrap.plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      debugPrint('notifications: requestPermission failed');
      return false;
    }
  }

  @override
  Future<void> show({
    required ReminderKind kind,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      final details = _detailsFor(kind);
      await NotificationBootstrap.plugin.show(
        _idFor(kind),
        title,
        body,
        details,
        payload: payload,
      );
    } catch (_) {
      debugPrint('notifications: show failed');
      rethrow;
    }
  }

  @override
  Future<void> schedule({
    required ReminderKind kind,
    required DateTime notifyAt,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      final when = notifyAt.toUtc();
      if (!when.isAfter(DateTime.now().toUtc())) {
        throw StateError('notify_at_not_future');
      }
      final scheduled = tz.TZDateTime.from(when, tz.UTC);
      await NotificationBootstrap.plugin.zonedSchedule(
        _idFor(kind),
        title,
        body,
        scheduled,
        _detailsFor(kind),
        androidScheduleMode: _scheduleMode,
        payload: payload,
      );
    } catch (_) {
      debugPrint('notifications: schedule failed');
      rethrow;
    }
  }

  @override
  Future<void> cancel(ReminderKind kind) async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      await NotificationBootstrap.plugin.cancel(_idFor(kind));
    } catch (_) {
      debugPrint('notifications: cancel failed');
      rethrow;
    }
  }

  @override
  Future<void> cancelAllReminders() async {
    try {
      await NotificationBootstrap.ensureInitializedOrThrow();
      await NotificationBootstrap.plugin.cancel(ReminderNotificationIds.resin);
      await NotificationBootstrap.plugin
          .cancel(ReminderNotificationIds.expedition);
    } catch (_) {
      debugPrint('notifications: cancelAll failed');
      rethrow;
    }
  }

  static int _idFor(ReminderKind kind) => switch (kind) {
        ReminderKind.resin => ReminderNotificationIds.resin,
        ReminderKind.expedition => ReminderNotificationIds.expedition,
      };

  static NotificationDetails _detailsFor(ReminderKind kind) {
    final channelId = switch (kind) {
      ReminderKind.resin => ReminderNotificationIds.resinChannelId,
      ReminderKind.expedition => ReminderNotificationIds.expeditionChannelId,
    };
    final channelName = switch (kind) {
      ReminderKind.resin => '樹脂リマインダー',
      ReminderKind.expedition => '探索派遣リマインダー',
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: switch (kind) {
          ReminderKind.resin => '天然樹脂が190に達したときの通知',
          ReminderKind.expedition => '探索派遣がすべて完了したときの通知',
        },
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
  }
}

/// Test double / no-op scheduler.
class RecordingNotificationScheduler implements NotificationScheduler {
  final List<String> ops = [];
  bool permissionGranted = true;
  bool failShow = false;
  bool failSchedule = false;
  bool failCancel = false;

  @override
  Future<bool> areNotificationsEnabled() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> show({
    required ReminderKind kind,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (failShow) throw StateError('show_failed');
    ops.add('show:${kind.name}');
  }

  @override
  Future<void> schedule({
    required ReminderKind kind,
    required DateTime notifyAt,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (failSchedule) throw StateError('schedule_failed');
    ops.add('schedule:${kind.name}:${notifyAt.toUtc().toIso8601String()}');
  }

  @override
  Future<void> cancel(ReminderKind kind) async {
    if (failCancel) throw StateError('cancel_failed');
    ops.add('cancel:${kind.name}');
  }

  @override
  Future<void> cancelAllReminders() async {
    if (failCancel) throw StateError('cancel_failed');
    ops.add('cancelAll');
  }
}
