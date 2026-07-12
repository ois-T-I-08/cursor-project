import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'reminder_models.dart';

/// Routes notification taps to Home without holding BuildContext statically.
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
    _goHome(router);
  }

  static void _consumePending() {
    final pending = _pendingPayload;
    if (pending == null) return;
    _pendingPayload = null;
    final router = _router;
    if (router == null) return;
    _goHome(router);
  }

  static void _goHome(GoRouter router) {
    try {
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      if (loc == '/') return;
      router.go('/');
    } catch (_) {
      try {
        router.go('/');
      } catch (_) {
        debugPrint('notifications: home navigation failed');
      }
    }
  }

  static bool _isAllowedPayload(String? payload) {
    return payload == ReminderNotificationIds.resinPayload ||
        payload == ReminderNotificationIds.expeditionPayload;
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
