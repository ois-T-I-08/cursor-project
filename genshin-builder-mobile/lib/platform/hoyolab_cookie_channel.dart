import 'package:flutter/services.dart';

import '../data/hoyolab/native_cookie_fetch_result.dart';

/// Android native CookieManager via MethodChannel.
class HoyolabCookieChannel {
  static const _channel = MethodChannel(
    'genshin_builder_mobile/hoyolab_cookie',
  );

  /// Fetches raw cookie string status. Does not log cookie bodies.
  static Future<NativeCookieFetchResult> fetchNativeCookie() async {
    try {
      final cookie = await _channel.invokeMethod<String>('fetchCookie');
      if (cookie == null || cookie.isEmpty) {
        return const NativeCookieFetchResult.absent();
      }
      return NativeCookieFetchResult.ok(cookie);
    } on MissingPluginException {
      return const NativeCookieFetchResult.pluginMissing();
    } on PlatformException catch (e) {
      if (e.code == 'COOKIE_MANAGER_ERROR') {
        return const NativeCookieFetchResult.managerError();
      }
      // Treat other platform errors as manager failures (still allow WebView fallback).
      return const NativeCookieFetchResult.managerError();
    }
  }
}
