import 'package:webview_flutter/webview_flutter.dart';

import '../../platform/hoyolab_cookie_channel.dart';

/// WebView / ネイティブから HoYoLAB Cookie を取得
class HoyolabCookieService {
  const HoyolabCookieService();

  static const _cookieDomains = [
    'https://m.hoyolab.com',
    'https://www.hoyolab.com',
    'https://act.hoyolab.com',
    'https://account.hoyolab.com',
  ];

  Future<String?> fetchCookieString() async {
    final native = await HoyolabCookieChannel.fetchNativeCookie();
    if (_hasAuthCookie(native)) return _normalize(native!);

    final manager = WebViewCookieManager();
    final merged = <String, String>{};

    for (final domain in _cookieDomains) {
      final cookies = await manager.getCookies(domain: Uri.parse(domain));
      for (final cookie in cookies) {
        if (cookie.name.isEmpty) continue;
        merged[cookie.name] = cookie.value;
      }
    }

    if (merged.isEmpty) return null;
    final cookie = merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (!_hasAuthCookie(cookie)) return null;
    return _normalize(cookie);
  }

  Future<bool> hasAuthCookie() async {
    final cookie = await fetchCookieString();
    return cookie != null;
  }

  static bool _hasAuthCookie(String? cookie) {
    if (cookie == null || cookie.isEmpty) return false;
    return cookie.contains('ltoken_v2=') ||
        cookie.contains('ltoken=') ||
        cookie.contains('ltuid_v2=') ||
        cookie.contains('account_id_v2=');
  }

  static String _normalize(String cookie) {
    final trimmed = cookie.trim();
    return trimmed.endsWith(';') ? trimmed : '$trimmed;';
  }
}
