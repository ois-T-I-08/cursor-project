import 'package:flutter/services.dart';

/// Opens the system app notification settings (Android).
class AppNotificationSettingsChannel {
  static const _channel =
      MethodChannel('genshin_builder_mobile/app_notification_settings');

  static Future<bool> open() async {
    try {
      final ok = await _channel.invokeMethod<bool>('open');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
