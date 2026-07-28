import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/build_recommendations/backend_build_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/build_recommendations/build_recommendation.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';

void main() {
  test('accepts only safe HTTPS YouTube guide URLs', () {
    expect(
      isSafeYoutubeGuideUrl('https://www.youtube.com/watch?v=abcdefghijk'),
      isTrue,
    );
    expect(isSafeYoutubeGuideUrl('https://youtu.be/abcdefghijk'), isTrue);
    expect(
      isSafeYoutubeGuideUrl('http://www.youtube.com/watch?v=abcdefghijk'),
      isFalse,
    );
    expect(
      isSafeYoutubeGuideUrl(
        'https://youtube.com.evil.example/watch?v=abcdefghijk',
      ),
      isFalse,
    );
    expect(isSafeYoutubeGuideUrl('javascript:alert(1)'), isFalse);
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
