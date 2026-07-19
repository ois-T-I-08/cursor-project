import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_builder_mobile/data/abyss/backend_abyss_statistics_api.dart';
import 'package:genshin_builder_mobile/data/abyss/http_abyss_statistics_repository.dart';
import 'package:genshin_builder_mobile/domain/abyss/abyss_statistics.dart';

void main() {
  group('BackendAbyssStatisticsApi', () {
    test('calls only the configured backend and converts valid DTO', () async {
      late http.Request captured;
      final api = BackendAbyssStatisticsApi(
        baseUrl: 'https://builder.example/base/',
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_validEnvelope()), 200);
        }),
      );

      final result = await api.fetchLatest();

      expect(
        captured.url.toString(),
        'https://builder.example/api/abyss/statistics',
      );
      expect(captured.headers['Accept'], 'application/json');
      expect(
        captured.headers['User-Agent'],
        contains('genshin-builder-mobile'),
      );
      expect(result.version.scheduleId, 106);
      expect(result.version.sourceApiVersion, '1.4.0');
      expect(result.metadata.sampleSize, 42);
      expect(result.characters.single.usageRate, 0.876);
      expect(result.characters.single.upperHalfRate, 0.4);
      expect(result.characters.single.lowerHalfRate, 0.6);
      expect(result.characters.single.weapons.single.id, '13509');
      expect(result.teams.single.members, hasLength(4));
    });

    test(
      'accepts successful empty statistics for the empty UI state',
      () async {
        final body = _validEnvelope();
        final data = body['data']! as Map<String, Object?>;
        data['characters'] = <Object?>[];
        data['teams'] = <Object?>[];
        final api = _apiFor(body);

        final result = await api.fetchLatest();

        expect(result.isEmpty, isTrue);
      },
    );

    test('preserves stale metadata and safe warning codes', () async {
      final body = _validEnvelope();
      final data = body['data']! as Map<String, Object?>;
      final metadata = data['metadata']! as Map<String, Object?>;
      metadata['isStale'] = true;
      metadata['warningCode'] = 'staleCache';
      metadata['upstreamErrorCode'] = 'timeout';

      final result = await _apiFor(body).fetchLatest();

      expect(result.metadata.isStale, isTrue);
      expect(result.metadata.warningCode, AbyssStatisticsFailure.staleCache);
      expect(result.metadata.upstreamErrorCode, AbyssStatisticsFailure.timeout);
    });

    test('accepts missing optional character and warning fields', () async {
      final body = _validEnvelope();
      final data = body['data']! as Map<String, Object?>;
      final metadata = data['metadata']! as Map<String, Object?>;
      final character =
          (data['characters']! as List<Object?>).single as Map<String, Object?>;
      metadata.remove('warningCode');
      metadata.remove('upstreamErrorCode');
      character.remove('upperHalfRate');
      character.remove('lowerHalfRate');

      final result = await _apiFor(body).fetchLatest();

      expect(result.metadata.warningCode, isNull);
      expect(result.metadata.upstreamErrorCode, isNull);
      expect(result.characters.single.upperHalfRate, isNull);
      expect(result.characters.single.lowerHalfRate, isNull);
    });

    test('rejects a missing required field', () async {
      final body = _validEnvelope();
      final data = body['data']! as Map<String, Object?>;
      final character =
          (data['characters']! as List<Object?>).single as Map<String, Object?>;
      character.remove('usageRate');

      await expectLater(
        _apiFor(body).fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.invalidResponse),
      );
    });

    test('rejects percentages outside zero to one', () async {
      final body = _validEnvelope();
      final data = body['data']! as Map<String, Object?>;
      final character =
          (data['characters']! as List<Object?>).single as Map<String, Object?>;
      character['usageRate'] = 1.01;

      await expectLater(
        _apiFor(body).fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.invalidResponse),
      );
    });

    test('maps backend error envelope without exposing its message', () async {
      final api = BackendAbyssStatisticsApi(
        baseUrl: 'https://builder.example',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': {
                'code': 'rateLimited',
                'message': 'private upstream detail',
              },
            }),
            429,
          ),
        ),
      );

      await expectLater(
        api.fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.rateLimited),
      );
    });

    test('fails safely when backend base URL is not configured', () async {
      final api = BackendAbyssStatisticsApi(
        baseUrl: '',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        api.fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.notConfigured),
      );
    });

    test('rejects plain HTTP except for local development hosts', () async {
      final api = BackendAbyssStatisticsApi(
        baseUrl: 'http://builder.example',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        api.fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.notConfigured),
      );
    });

    test('repository returns the normalized backend result', () async {
      final repository = HttpAbyssStatisticsRepository(
        _apiFor(_validEnvelope()),
      );

      final result = await repository.fetchLatest();

      expect(result.metadata.source, AbyssDataSource.aza);
      expect(result.characters.single.usageRate, 0.876);
    });

    test('repository preserves typed backend failures', () async {
      final api = BackendAbyssStatisticsApi(
        baseUrl: 'https://builder.example',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': {'code': 'timeout', 'message': 'safe'},
            }),
            504,
          ),
        ),
      );
      final repository = HttpAbyssStatisticsRepository(api);

      await expectLater(
        repository.fetchLatest(),
        _throwsFailure(AbyssStatisticsFailure.timeout),
      );
    });
  });
}

BackendAbyssStatisticsApi _apiFor(Map<String, Object?> body) {
  return BackendAbyssStatisticsApi(
    baseUrl: 'https://builder.example',
    client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
  );
}

Matcher _throwsFailure(AbyssStatisticsFailure failure) {
  return throwsA(
    isA<AbyssStatisticsException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );
}

Map<String, Object?> _validEnvelope() {
  return {
    'ok': true,
    'data': {
      'version': {
        'scheduleId': 106,
        'periodStart': '2026-07-16T00:00:00.000Z',
        'periodEnd': '2026-08-01T00:00:00.000Z',
        'sourceApiVersion': '1.4.0',
      },
      'metadata': {
        'source': 'AZA.GG',
        'fetchedAt': '2026-07-19T01:30:00.000Z',
        'expiresAt': '2026-07-19T07:30:00.000Z',
        'sourceUpdatedAt': '2026-07-19T00:00:00.000Z',
        'isStale': false,
        'sampleSize': 42,
        'referenceSampleSize': 84,
        'collectionProgress': 0.5,
        'warningCode': null,
        'upstreamErrorCode': null,
      },
      'characters': [
        {
          'characterId': '10000052',
          'usageRate': 0.876,
          'ownershipRate': 0.8,
          'usageAmongOwnersRate': 0.75,
          'upperHalfRate': 0.4,
          'lowerHalfRate': 0.6,
          'constellationRates': [
            {'constellation': 0, 'rate': 0.5},
          ],
          'weapons': [
            {'id': '13509', 'usageRate': 0.4},
          ],
          'artifacts': [
            {
              'setPieces': [
                {'artifactSetId': '15020', 'pieces': 4},
              ],
              'usageRate': 0.7,
            },
          ],
        },
      ],
      'teams': [
        {
          'half': 'upper',
          'members': ['10000052', '10000023', '10000054', '10000032'],
          'usageRate': 0.3,
          'ownershipRate': 0.2,
          'usageAmongOwnersRate': 0.25,
        },
      ],
    },
  };
}
