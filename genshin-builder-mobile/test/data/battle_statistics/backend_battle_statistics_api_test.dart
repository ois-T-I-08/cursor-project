import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_builder_mobile/data/battle_statistics/backend_battle_statistics_api.dart';
import 'package:genshin_builder_mobile/domain/battle_statistics/battle_statistics.dart';

void main() {
  test(
    'manifest sends ETag and accepts 304 without downloading a bundle',
    () async {
      final client = MockClient((request) async {
        expect(request.headers['if-none-match'], '"fixture"');
        return http.Response('', 304);
      });
      final api = BackendBattleStatisticsApi(
        baseUrl: 'https://builder.example.com',
        client: client,
      );

      final result = await api.fetchManifest(etag: '"fixture"');
      expect(result.notModified, isTrue);
      expect(result.manifest, isNull);
    },
  );

  test('strictly parses a paged public bundle', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['type'], 'abyss');
      expect(request.url.queryParameters['revision'], '2');
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'schemaVersion': 1,
            'source': 'YShelper',
            'contentType': 'abyss',
            'sourceVersion': 'fixture-1',
            'seasonId': 'season',
            'revision': 2,
            'payloadHash':
                'sha256:0000000000000000000000000000000000000000000000000000000000000000',
            'sourceUpdatedAt': '2026-07-24T00:00:00.000Z',
            'sampleSize': 1000,
            'metadata': <String, Object>{},
            'page': 0,
            'pageCount': 1,
            'teams': [
              {
                'teamKey': '10000001:10000002:10000003:10000004',
                'members': ['10000001', '10000002', '10000003', '10000004'],
                'usageRate': 0.25,
                'usageCount': 250,
                'rank': 1,
                'side': 'upper',
                'stageKey': '12-1',
                'sampleSize': 1000,
              },
            ],
            'characters': [
              {
                'characterId': '10000001',
                'usageRate': 0.5,
                'usageCount': 500,
                'rank': 1,
                'side': 'upper',
                'ownershipRate': 0.8,
                'usageAmongOwnersRate': 0.625,
                'sampleSize': 1000,
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = BackendBattleStatisticsApi(
      baseUrl: 'https://builder.example.com',
      client: client,
    );

    final page = await api.fetchBundlePage(
      contentType: BattleStatsContentType.abyss,
      revision: 2,
      page: 0,
    );
    expect(page.teams.single.members, hasLength(4));
    expect(page.characters.single.usageRate, 0.5);
  });

  test('rejects a mismatched team key', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'schemaVersion': 1,
            'source': 'YShelper',
            'contentType': 'abyss',
            'sourceVersion': 'fixture-1',
            'seasonId': 'season',
            'revision': 2,
            'payloadHash':
                'sha256:0000000000000000000000000000000000000000000000000000000000000000',
            'sourceUpdatedAt': '2026-07-24T00:00:00.000Z',
            'sampleSize': null,
            'metadata': <String, Object>{},
            'page': 0,
            'pageCount': 1,
            'teams': [
              {
                'teamKey': 'wrong',
                'members': ['10000001', '10000002', '10000003', '10000004'],
                'usageRate': 0.25,
                'usageCount': null,
                'rank': null,
                'side': null,
                'stageKey': null,
                'sampleSize': null,
              },
            ],
            'characters': <Object>[],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = BackendBattleStatisticsApi(
      baseUrl: 'https://builder.example.com',
      client: client,
    );

    await expectLater(
      api.fetchBundlePage(
        contentType: BattleStatsContentType.abyss,
        revision: 2,
        page: 0,
      ),
      throwsA(isA<BattleStatsRemoteException>()),
    );
  });
}
