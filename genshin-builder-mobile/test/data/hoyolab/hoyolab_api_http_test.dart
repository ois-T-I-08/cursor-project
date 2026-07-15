import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_api.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_http_guard.dart';

void main() {
  group('HoyolabApi HTTP guard integration', () {
    test('rejects 502 HTML before JSON parsing', () async {
      final api = HoyolabApi(
        cookie: 'ltoken_v2=test; ltuid_v2=1;',
        client: MockClient(
          (_) async => http.Response('<html>upstream</html>', 502),
        ),
      );

      await expectLater(
        api.verifyLToken(),
        throwsA(isA<HoyolabHttpException>()),
      );
    });

    test('parses successful verify response', () async {
      final api = HoyolabApi(
        cookie: 'ltoken_v2=test; ltuid_v2=1;',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'retcode': 0,
              'message': 'OK',
              'data': {
                'user_info': {
                  'account_name': 'traveler',
                },
              },
            }),
            200,
          ),
        ),
      );

      final user = await api.verifyLToken();
      expect(user.accountName, 'traveler');
    });

    test('requires cookie before network access', () async {
      final api = HoyolabApi(
        cookie: '',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(() => api.verifyLToken(), throwsStateError);
    });
  });
}
