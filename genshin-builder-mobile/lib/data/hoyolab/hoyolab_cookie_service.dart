import 'package:webview_flutter/webview_flutter.dart';

import '../../platform/hoyolab_cookie_channel.dart';
import 'hoyolab_cookie_normalizer.dart';
import 'native_cookie_fetch_result.dart';

/// Collects HoYoLAB cookies from WebView (preferred) and native CookieManager.
class HoyolabCookieService {
  const HoyolabCookieService({
    this.webViewCookieReader,
    this.nativeCookieFetcher,
  });

  /// Test seam for WebView cookies (name→value).
  final Future<Map<String, String>> Function()? webViewCookieReader;

  /// Test seam for native channel result.
  final Future<NativeCookieFetchResult> Function()? nativeCookieFetcher;

  static const _cookieDomains = [
    'https://m.hoyolab.com',
    'https://www.hoyolab.com',
    'https://act.hoyolab.com',
    'https://account.hoyolab.com',
  ];

  /// Returns a normalized Cookie header, or null if no usable token cookie.
  ///
  /// Priority: WebView values win; native only fills keys missing from WebView.
  Future<String?> collectNormalizedCookie() async {
    final webViewMap = await _readWebViewCookies();
    final nativeResult =
        await (nativeCookieFetcher ?? HoyolabCookieChannel.fetchNativeCookie)();
    final nativeMap =
        nativeResult.isOk
            ? HoyolabCookieNormalizer.parseToMap(nativeResult.value)
            : null;

    final merged = HoyolabCookieNormalizer.mergePreferBase(
      base: webViewMap,
      fill: nativeMap ?? const {},
    );
    if (merged.isEmpty) return null;
    if (!HoyolabCookieNormalizer.hasRequiredToken(merged)) return null;
    return HoyolabCookieNormalizer.serialize(merged);
  }

  /// Legacy helper used by tests / call sites that only need presence.
  Future<String?> fetchCookieString() => collectNormalizedCookie();

  Future<bool> hasAuthCookie() async {
    final cookie = await collectNormalizedCookie();
    return cookie != null;
  }

  Future<Map<String, String>> _readWebViewCookies() async {
    if (webViewCookieReader != null) {
      return Map<String, String>.from(await webViewCookieReader!());
    }

    final manager = WebViewCookieManager();
    final merged = <String, String>{};
    for (final domain in _cookieDomains) {
      try {
        final cookies = await manager.getCookies(domain: Uri.parse(domain));
        for (final cookie in cookies) {
          final name = cookie.name.trim();
          final value = cookie.value.trim();
          if (name.isEmpty || value.isEmpty) continue;
          // Later domains overwrite earlier ones within WebView source.
          merged[name] = value;
        }
      } catch (_) {
        // Continue other domains; never log cookie bodies.
      }
    }
    return merged;
  }
}
