import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/amber/amber_upgrade.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AmberUpgradeApi.fetchWeaponUpgrade', () {
    test('returns null when upgrade is missing (mannequin weapons)', () async {
      final api = AmberUpgradeApi(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'response': 200,
              'data': {
                'name': 'マネキン剣',
                'items': <String, dynamic>{},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.fetchWeaponUpgrade('310001');
      expect(result, isNull);
      api.dispose();
    });

    test('returns null when promote list is empty', () async {
      final api = AmberUpgradeApi(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'response': 200,
              'data': {
                'upgrade': {'promote': <dynamic>[]},
                'items': <String, dynamic>{},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.fetchWeaponUpgrade('310001');
      expect(result, isNull);
      api.dispose();
    });
  });
}
