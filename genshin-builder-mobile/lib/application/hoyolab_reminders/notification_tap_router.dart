import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../daily_plan_notifications/daily_plan_notification_ids.dart';
import 'reminder_models.dart';

/// Routes notification taps without holding BuildContext statically.
class NotificationTapRouter {
  NotificationTapRouter._();

  static GoRouter? _router;
  static String? _pendingPayload;
  static bool _consumedLaunch = false;

  static void attachRouter(GoRouter router) {
    _router = router;
    _consumePending();
  }

  static void onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (!_isAllowedPayload(payload)) return;
    _navigateOrPending(payload!);
  }

  static Future<void> captureLaunchDetails(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (_consumedLaunch) return;
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final payload = details!.notificationResponse?.payload;
      if (!_isAllowedPayload(payload)) return;
      _consumedLaunch = true;
      _navigateOrPending(payload!);
    } catch (_) {
      debugPrint('notifications: launch details failed');
    }
  }

  static void _navigateOrPending(String payload) {
    final router = _router;
    if (router == null) {
      _pendingPayload = payload;
      return;
    }
    _goForPayload(router, payload);
  }

  static void _consumePending() {
    final pending = _pendingPayload;
    if (pending == null) return;
    _pendingPayload = null;
    final router = _router;
    if (router == null) return;
    _goForPayload(router, pending);
  }

  static void _goForPayload(GoRouter router, String payload) {
    if (payload == DailyPlanNotificationIds.incompletePayload) {
      _goPath(router, '/daily-plan');
      return;
    }
    _goPath(router, '/');
  }

  static void _goPath(GoRouter router, String path) {
    try {
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      if (loc == path) return;
      router.go(path);
    } catch (_) {
      try {
        router.go(path);
      } catch (_) {
        debugPrint('notifications: navigation failed');
      }
    }
  }

  static bool _isAllowedPayload(String? payload) {
    return payload == ReminderNotificationIds.resinPayload ||
        payload == ReminderNotificationIds.expeditionPayload ||
        payload == DailyPlanNotificationIds.incompletePayload;
  }

  @visibleForTesting
  static void debugReset() {
    _router = null;
    _pendingPayload = null;
    _consumedLaunch = false;
  }

  @visibleForTesting
  static void debugSetPending(String payload) {
    _pendingPayload = payload;
  }

  @visibleForTesting
  static String? get debugPendingPayload => _pendingPayload;
}
