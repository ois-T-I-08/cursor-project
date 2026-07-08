import 'package:flutter/services.dart';

/// Android ネイティブ CookieManager 経由で HoYoLAB Cookie を取得
class HoyolabCookieChannel {
  static const _channel = MethodChannel('genshin_builder_mobile/hoyolab_cookie');

  static Future<String?> fetchNativeCookie() async {
    try {
      final cookie = await _channel.invokeMethod<String>('fetchCookie');
      if (cookie == null || cookie.isEmpty) return null;
      return cookie;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
