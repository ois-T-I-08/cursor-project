import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'notification_tap_router.dart';

/// Single-flight, idempotent plugin bootstrap (no permission prompt).
class NotificationBootstrap {
  NotificationBootstrap._();

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void>? _initializing;
  static bool _initialized = false;
  static bool _initFailed = false;

  static bool get isInitialized => _initialized;
  static bool get initFailed => _initFailed;

  /// Safe to call concurrently; failures do not throw to callers by default.
  static Future<void> ensureInitialized() {
    if (_initialized) return Future<void>.value();
    if (_initFailed) return Future<void>.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  /// Awaits init and rethrows on failure (scheduler ops use this).
  static Future<void> ensureInitializedOrThrow() async {
    await ensureInitialized();
    if (!_initialized) {
      throw StateError('notification_init_failed');
    }
  }

  static Future<void> _doInitialize() async {
    try {
      tz_data.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );

      final ok = await plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: NotificationTapRouter.onResponse,
      );
      if (ok == false) {
        _initFailed = true;
        debugPrint('notifications: initialize returned false');
        return;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'resin_reminders',
            '樹脂リマインダー',
            description: '天然樹脂が190に達したときの通知',
            importance: Importance.defaultImportance,
          ),
        );
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'expedition_reminders',
            '探索派遣リマインダー',
            description: '探索派遣がすべて完了したときの通知',
            importance: Importance.defaultImportance,
          ),
        );
      }

      await NotificationTapRouter.captureLaunchDetails(plugin);
      _initialized = true;
    } catch (e) {
      _initFailed = true;
      debugPrint('notifications: initialize failed');
    }
  }

  /// Test-only reset.
  @visibleForTesting
  static void debugReset() {
    _initializing = null;
    _initialized = false;
    _initFailed = false;
  }
}
