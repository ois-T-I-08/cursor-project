import 'package:genshin_builder_mobile/domain/build_recommendations/build_recommendation.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';

/// Widget / パーサーテスト用の構造化サンプル（本番データではない）
CharacterBuildRecommendation buildRecommendationFixture({
  String characterId = '10000046',
  InvestmentPriority investmentPriority = InvestmentPriority.high,
  List<GuideWeaponRecommendation> weapons = const [],
  List<GuideArtifactRecommendation> artifactRecommendations = const [],
  List<GuideMainStatRecommendation> mainStats = const [],
  String? weaponPreference,
  String? gameVersion = '5.8',
  DateTime? lastVerifiedAt,
  List<BuildRecommendationSource> sources = const [],
  List<BuildStatTarget> targets = const [],
}) {
  return CharacterBuildRecommendation(
    characterId: characterId,
    label: '動画内推奨目安',
    origin: BuildRecommendationOrigin.singleVideo,
    overallConfidence: 0.9,
    targets: targets,
    substatPriority: const [StatKey.critRate, StatKey.critDmg],
    caveats: const [],
    sources: sources,
    evidence: const [],
    mainStats: mainStats,
    weapons: weapons,
    artifactRecommendations: artifactRecommendations,
    weaponPreference: weaponPreference,
    investmentPriority: investmentPriority,
    gameVersion: gameVersion,
    lastVerifiedAt: lastVerifiedAt ?? DateTime.utc(2026, 7, 1),
    role: 'dps',
  );
}

Map<String, Object?> structuredRecommendationJson() => {
      'characterId': '10000046',
      'label': '動画内推奨目安',
      'status': 'published',
      'origin': 'single_video',
      'overallConfidence': 0.9,
      'investmentPriority': 'high',
      'gameVersion': '5.8',
      'context': {
        'role': 'dps',
        'weaponPreference': '旧文字列は無視されるはず',
      },
      'weapons': <Object?>[
        {
          'weaponId': 'w1',
          'displayName': '護摩の杖',
          'rank': 1,
          'recommendationLevel': 'strongly_recommended',
          'reason': 'HP変換と会心が噛み合う',
          'conditions': <Object?>['HP確保時'],
          'source': 'vid1',
        },
        {
          'weaponId': 'w2',
          'rank': 2,
          'reason': '無課金向け',
          'conditions': <Object?>[],
        },
      ],
      'artifactRecommendations': <Object?>[
        {
          'sets': <Object?>[
            {'setId': '15020', 'pieces': 4},
          ],
          'rank': 1,
          'recommendationLevel': 'recommended',
          'reason': '爆発特化の定番4セット',
          'conditions': <Object?>[],
          'source': {
            'videoId': 'vid1',
            'channelName': 'Sample Channel',
          },
        },
        {
          'sets': <Object?>[
            {'setId': '15017', 'pieces': 2},
            {'setId': '15008', 'pieces': 2},
          ],
          'rank': 2,
          'isAlternative': true,
          'reason': '2+2の状況依存構成',
          'role': 'サブアタッカー',
        },
      ],
      'mainStats': <Object?>[
        {
          'slot': 'sands',
          'stats': <Object?>['元素熟知', '攻撃力%'],
          'condition': '武器でチャージを確保できる場合',
        },
        {
          'slot': 'goblet',
          'stats': <Object?>['炎元素ダメージ'],
        },
        {
          'slot': 'circlet',
          'stats': <Object?>['会心率', '会心ダメージ'],
        },
      ],
      'substatPriority': <Object?>['critRate', 'critDmg'],
      'targets': <Object?>[
        {
          'stat': 'er',
          'min': 180,
          'max': 220,
          'unit': 'percent',
        },
      ],
      'caveats': <Object?>[],
      'sources': <Object?>[
        {
          'videoId': 'vid1',
          'title': '胡桃ガイド',
          'channelTitle': 'Sample Channel',
          'channelId': 'UC123',
          'sourceUrl': 'https://www.youtube.com/watch?v=vid1',
          'publishedAt': '2026-06-01T00:00:00.000Z',
          'reviewedAt': '2026-07-01T00:00:00.000Z',
          'gameVersion': '5.8',
        },
      ],
      'evidence': <Object?>[],
      'lastVerifiedAt': '2026-07-01T00:00:00.000Z',
    };
