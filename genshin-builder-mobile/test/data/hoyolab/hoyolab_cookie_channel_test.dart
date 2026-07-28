import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_cookie_service.dart';
import 'package:genshin_builder_mobile/data/hoyolab/native_cookie_fetch_result.dart';
import 'package:genshin_builder_mobile/platform/hoyolab_cookie_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('genshin_builder_mobile/hoyolab_cookie');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('HoyolabCookieChannel', () {
    test('maps non-empty string to ok', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'fetchCookie');
            return 'ltoken_v2=dummy_native';
          });
      final r = await HoyolabCookieChannel.fetchNativeCookie();
      expect(r.status, NativeCookieFetchStatus.ok);
      expect(r.value, 'ltoken_v2=dummy_native');
    });

    test('maps null to absent', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final r = await HoyolabCookieChannel.fetchNativeCookie();
      expect(r.status, NativeCookieFetchStatus.absent);
    });

    test('maps empty string to absent', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => '');
      final r = await HoyolabCookieChannel.fetchNativeCookie();
      expect(r.status, NativeCookieFetchStatus.absent);
    });

    test('maps COOKIE_MANAGER_ERROR to managerError', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'COOKIE_MANAGER_ERROR',
              message: 'Cookie manager failed',
            );
          });
      final r = await HoyolabCookieChannel.fetchNativeCookie();
      expect(r.status, NativeCookieFetchStatus.managerError);
    });

    test('maps MissingPluginException to pluginMissing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException('no plugin');
          });
      final r = await HoyolabCookieChannel.fetchNativeCookie();
      expect(r.status, NativeCookieFetchStatus.pluginMissing);
    });
  });

  group('HoyolabCookieService fallback', () {
    test('continues with WebView cookie when native managerError', () async {
      final service = HoyolabCookieService(
        webViewCookieReader:
            () async => {'ltoken_v2': 'dummy_from_webview', 'ltuid_v2': '1'},
        nativeCookieFetcher:
            () async => const NativeCookieFetchResult.managerError(),
      );
      final cookie = await service.collectNormalizedCookie();
      expect(cookie, isNotNull);
      expect(cookie!.contains('ltoken_v2=dummy_from_webview'), isTrue);
      expect(cookie.contains('ltoken_v2=dummy_from_native'), isFalse);
    });

    test('WebView wins over native on same key', () async {
      final service = HoyolabCookieService(
        webViewCookieReader: () async => {'ltoken_v2': 'dummy_webview'},
        nativeCookieFetcher:
            () async => const NativeCookieFetchResult.ok(
              'ltoken_v2=dummy_native; extra=native_only',
            ),
      );
      final cookie = await service.collectNormalizedCookie();
      expect(cookie, contains('ltoken_v2=dummy_webview'));
      expect(cookie, contains('extra=native_only'));
      expect(cookie!.contains('dummy_native'), isFalse);
    });
  });
}
