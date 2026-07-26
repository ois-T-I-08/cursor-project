import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/build_recommendations/backend_build_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/build_recommendations/build_recommendation.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';

void main() {
  test('parses public recommendation payload', () {
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
          'fieldPath': 'targets.critRate',
          'snippet': '会心率70',
          'videoId': 'abcdefghijk',
        },
      ],
    });

    expect(parsed.characterId, 'hu-tao');
    expect(parsed.label, '動画内推奨目安');
    expect(parsed.targets.single.stat, StatKey.critRate);
    expect(parsed.substatPriority.first, StatKey.critRate);
  });

  test('compareStatToTarget classifies ranges', () {
    const target = BuildStatTarget(
      stat: StatKey.critRate,
      min: 60,
      recommended: 70,
      max: 80,
    );
    expect(compareStatToTarget(current: 55, target: target), StatCompareVerdict.below);
    expect(compareStatToTarget(current: 70, target: target), StatCompareVerdict.within);
    expect(compareStatToTarget(current: 90, target: target), StatCompareVerdict.above);
  });
}
