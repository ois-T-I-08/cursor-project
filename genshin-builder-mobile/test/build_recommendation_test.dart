import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/build_recommendations/backend_build_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/build_recommendations/build_recommendation.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('accepts only the explicit HTTPS YouTube guide hosts', () {
    const allowed = [
      'https://youtube.com/',
      'https://www.youtube.com/',
      'https://m.youtube.com/',
      'https://youtu.be/',
    ];
    const rejected = [
      'http://www.youtube.com/watch?v=abcdefghijk',
      'javascript:alert(1)',
      'data:text/plain,hello',
      'file:///tmp/video',
      'ftp://youtube.com/video',
      'https://youtube.com.evil.example/watch?v=abcdefghijk',
      'https://youtube.example/watch?v=abcdefghijk',
      'https://user:pass@youtube.com/watch?v=abcdefghijk',
      'https://www.youtube.com@evil.example/watch?v=abcdefghijk',
      'https://music.youtube.com/watch?v=abcdefghijk',
      'https://www.youtube.com./watch?v=abcdefghijk',
      'https://xn--.com/',
      '',
      '/watch?v=abcdefghijk',
    ];

    for (final url in allowed) {
      expect(isSafeYoutubeGuideUrl(url), isTrue, reason: url);
    }
    for (final url in rejected) {
      expect(isSafeYoutubeGuideUrl(url), isFalse, reason: url);
    }
  });

  test('parses visual recommendation payload', () {
    final parsed = parseBuildRecommendation({
      'characterId': 'hu-tao',
      'label': '動画内推奨目安',
      'status': 'published',
      'origin': 'single_video',
      'overallConfidence': 0.8,
      'context': {'role': 'dps'},
      'mainStats': <Object?>[],
      'substatPriority': <Object?>['critRate', 'critDmg'],
      'targets': <Object?>[
        {
          'stat': 'critRate',
          'recommended': 70,
          'min': 60,
          'max': 80,
          'unit': 'percent',
        },
      ],
      'caveats': <Object?>['編成バフは含みません'],
      'lastVerifiedAt': '2026-07-15T00:00:00.000Z',
      'publishedAt': '2026-07-15T00:00:00.000Z',
      'sources': <Object?>[
        {
          'videoId': 'abcdefghijk',
          'title': 'guide',
          'channelTitle': 'channel',
          'sourceUrl': 'https://www.youtube.com/watch?v=abcdefghijk',
        },
      ],
      'evidence': <Object?>[
        {
          'fieldPath': 'visual',
          'exactVisibleText': 'ER 150～160%',
          'videoId': 'abcdefghijk',
          'startSeconds': 530,
          'endSeconds': 545,
        },
      ],
    });

    expect(parsed.characterId, 'hu-tao');
    expect(parsed.label, '動画内推奨目安');
    expect(parsed.evidence.single.exactVisibleText, 'ER 150～160%');
    expect(parsed.evidence.single.startSeconds, 530);
  });

  test('drops unsafe source URLs from an otherwise valid payload', () {
    final parsed = parseBuildRecommendation({
      'characterId': 'hu-tao',
      'sources': <Object?>[
        {
          'videoId': 'unsafe',
          'title': 'unsafe',
          'channelTitle': 'channel',
          'sourceUrl': 'https://youtube.com.evil.example/watch?v=unsafe',
        },
        {
          'videoId': 'safe',
          'title': 'safe',
          'channelTitle': 'channel',
          'sourceUrl': 'https://www.youtube.com/watch?v=safe',
        },
      ],
    });
    expect(parsed.sources.map((source) => source.videoId), ['safe']);
  });

  test('parses schema v2 verification, availability, and timestamps', () {
    final parsed = parseBuildRecommendation({
      'schemaVersion': 2,
      'verificationMode': 'automatic_strict',
      'characterId': 'raiden-shogun',
      'sources': <Object?>[
        {
          'videoId': 'phase4Video',
          'title': 'guide',
          'channelTitle': 'channel',
          'sourceUrl': 'https://www.youtube.com/watch?v=phase4Video',
          'availability': 'unavailable',
          'unavailableSince': '2026-07-31T01:00:00.000Z',
        },
      ],
      'evidence': <Object?>[
        {
          'fieldPath': 'transcript',
          'videoId': 'phase4Video',
          'timestampStart': 20,
          'timestampEnd': 25,
        },
      ],
    });
    expect(parsed.schemaVersion, 2);
    expect(
      parsed.verificationMode,
      BuildRecommendationVerificationMode.automaticStrict,
    );
    expect(
      parsed.sources.single.availability,
      BuildRecommendationSourceAvailability.unavailable,
    );
    expect(parsed.evidence.single.exactVisibleText, isEmpty);
    expect(parsed.evidence.single.startSeconds, 20);
    expect(parsed.evidence.single.endSeconds, 25);
  });

  test('prefers v2 and falls back to the unchanged v1 endpoint', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.startsWith('/api/v2/')) {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'notFound'}),
          404,
        );
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'schemaVersion': 1,
            'characterId': 'raiden-shogun',
            'sources': <Object?>[],
            'evidence': <Object?>[],
          },
        }),
        200,
      );
    });
    final api = BackendBuildRecommendationApi(
      baseUrl: 'https://example.com',
      client: client,
    );
    final result = await api.fetchPublished('raiden-shogun');
    expect(result?.schemaVersion, 1);
    expect(requests.map((uri) => uri.path), [
      '/api/v2/build-recommendations/raiden-shogun',
      '/api/build-recommendations/raiden-shogun',
    ]);
  });

  test('never falls back for a non-404 v2 response', () async {
    for (final status in [401, 403, 500]) {
      final requests = <Uri>[];
      final api = BackendBuildRecommendationApi(
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({'ok': false, 'error': 'fixture'}),
            status,
          );
        }),
      );
      await expectLater(
        api.fetchPublished('raiden-shogun'),
        throwsA(
          isA<BuildRecommendationException>().having(
            (error) => error.failure,
            'failure',
            BuildRecommendationFailure.invalidResponse,
          ),
        ),
      );
      expect(requests, hasLength(1), reason: 'status=$status');
      expect(requests.single.path, startsWith('/api/v2/'));
    }
  });

  test('malformed v2 and unsupported schema never fall back', () async {
    for (final body in [
      '{not-json',
      jsonEncode({
        'ok': true,
        'data': {'schemaVersion': 99, 'characterId': 'raiden-shogun'},
      }),
    ]) {
      var calls = 0;
      final api = BackendBuildRecommendationApi(
        baseUrl: 'https://example.com',
        client: MockClient((_) async {
          calls += 1;
          return http.Response(body, 200);
        }),
      );
      await expectLater(
        api.fetchPublished('raiden-shogun'),
        throwsA(
          isA<BuildRecommendationException>().having(
            (error) => error.failure,
            'failure',
            BuildRecommendationFailure.invalidResponse,
          ),
        ),
      );
      expect(calls, 1);
    }
  });

  test('v2 timeout never falls back', () async {
    var calls = 0;
    final api = BackendBuildRecommendationApi(
      baseUrl: 'https://example.com',
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.fetchPublished('raiden-shogun'),
      throwsA(
        isA<BuildRecommendationException>().having(
          (error) => error.failure,
          'failure',
          BuildRecommendationFailure.timeout,
        ),
      ),
    );
    expect(calls, 1);
  });

  test('compareStatToTarget classifies ranges', () {
    const target = BuildStatTarget(
      stat: StatKey.critRate,
      min: 60,
      recommended: 70,
      max: 80,
    );
    expect(
      compareStatToTarget(current: 55, target: target),
      StatCompareVerdict.below,
    );
    expect(
      compareStatToTarget(current: 70, target: target),
      StatCompareVerdict.within,
    );
    expect(
      compareStatToTarget(current: 90, target: target),
      StatCompareVerdict.above,
    );
  });
}
