import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/hoyolab/complete_hoyolab_web_login_use_case.dart';
import 'package:genshin_builder_mobile/config/feature_flags.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_api.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_cookie_service.dart';
import 'package:genshin_builder_mobile/data/hoyolab/native_cookie_fetch_result.dart';
import 'package:genshin_builder_mobile/data/repositories/hoyolab_repository.dart';
import 'package:genshin_builder_mobile/data/secure/secure_storage_keys.dart';
import 'package:genshin_builder_mobile/data/secure/secure_storage_service.dart';
import 'package:http/http.dart' as http;

class _MemSecureStorage extends SecureStorageService {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async {
    map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    map.remove(key);
  }
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._bodies);

  final List<String> _bodies;
  var _i = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        _i < _bodies.length
            ? _bodies[_i++]
            : '{"retcode":-1,"message":"done","data":null}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('CompleteHoyolabWebLoginUseCase', () {
    test('success result type carries no cookie field', () {
      const result = HoyolabWebLoginResult.success();
      expect(result.success, isTrue);
      expect(result.userMessage, isNull);
    });

    test(
      'failure when cookie missing has no token material in message',
      () async {
        final useCase = CompleteHoyolabWebLoginUseCase(
          cookieService: HoyolabCookieService(
            webViewCookieReader: () async => {},
            nativeCookieFetcher:
                () async => const NativeCookieFetchResult.absent(),
          ),
          repository: HoyolabRepository(
            secureStorage: _MemSecureStorage(),
            featureFlags: FeatureFlags(hoyolabLinkEnabled: true),
          ),
        );
        final result = await useCase();
        expect(result.success, isFalse);
        final msg = result.userMessage!.toLowerCase();
        expect(msg, isNot(contains('ltoken')));
        expect(msg, isNot(contains('dummy_')));
        expect(result.userMessage, isNot(contains('=')));
      },
    );

    test('does not save cookie when verifyLToken fails', () async {
      final storage = _MemSecureStorage();
      final client = _ScriptedClient([
        '{"retcode":-100,"message":"ltoken=should_not_leak","data":null}',
      ]);
      final useCase = CompleteHoyolabWebLoginUseCase(
        cookieService: HoyolabCookieService(
          webViewCookieReader:
              () async => {'ltoken_v2': 'dummy_token_should_not_persist'},
          nativeCookieFetcher:
              () async => const NativeCookieFetchResult.absent(),
        ),
        repository: HoyolabRepository(
          secureStorage: storage,
          featureFlags: FeatureFlags(hoyolabLinkEnabled: true),
          apiFactory: ({required cookie, region, uid, appVersion = '4.13.0'}) {
            return HoyolabApi(
              cookie: cookie,
              appVersion: appVersion,
              client: client,
            );
          },
        ),
      );

      final result = await useCase();
      expect(result.success, isFalse);
      expect(storage.map.containsKey(SecureStorageKeys.cookie), isFalse);
      expect(result.userMessage!.toLowerCase(), isNot(contains('ltoken')));
      expect(result.userMessage, isNot(contains('should_not_leak')));
      expect(result.userMessage, isNot(contains('dummy_token')));
    });
  });
}
