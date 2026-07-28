import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/build_recommendations/backend_build_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/build_recommendations/guide_insight.dart';

import 'fixtures/build_recommendation_fixtures.dart';

void main() {
  group('parseInvestmentPriority', () {
    test('parses explicit values only', () {
      expect(parseInvestmentPriority('high'), InvestmentPriority.high);
      expect(parseInvestmentPriority('中'), InvestmentPriority.medium);
      expect(parseInvestmentPriority('low'), InvestmentPriority.low);
    });

    test('missing or unknown becomes none (no confidence fallback)', () {
      expect(parseInvestmentPriority(null), InvestmentPriority.none);
      expect(parseInvestmentPriority(''), InvestmentPriority.none);
      expect(parseInvestmentPriority('unknown'), InvestmentPriority.none);
    });
  });

  group('resolveYoutubeWeapons', () {
    test('prefers structured list over legacy preference', () {
      final structured = [
        const GuideWeaponRecommendation(weaponId: 'w1', rank: 1),
      ];
      final resolved = resolveYoutubeWeapons(
        structured: structured,
        legacyWeaponPreference: '護摩の杖、匣中滅龍',
      );
      expect(resolved, structured);
      expect(resolved.single.isLegacy, isFalse);
    });

    test('falls back to legacy preference when structured empty', () {
      final resolved = resolveYoutubeWeapons(
        structured: const [],
        legacyWeaponPreference: '護摩の杖、試作・斬岩 / 匣中滅龍',
      );
      expect(resolved.map((e) => e.displayName), ['護摩の杖', '試作・斬岩', '匣中滅龍']);
      expect(resolved.every((e) => e.isLegacy), isTrue);
    });
  });

  group('formatFreshnessCaption', () {
    test('version only does not claim latest', () {
      expect(formatFreshnessCaption(gameVersion: '5.8'), 'Ver.5.8時点');
    });

    test('marks older when current version is known', () {
      expect(
        formatFreshnessCaption(gameVersion: '5.2', currentGameVersion: '5.8'),
        contains('古い情報の可能性があります'),
      );
    });

    test('does not use lexical version order', () {
      // "9" < "10" lexically but numerically older
      expect(compareGameVersions('5.9', '5.10'), lessThan(0));
      expect(
        formatFreshnessCaption(gameVersion: '5.9', currentGameVersion: '5.10'),
        contains('古い情報の可能性があります'),
      );
    });

    test('date only and unknown', () {
      expect(
        formatFreshnessCaption(reviewedAt: DateTime.utc(2026, 7, 1)),
        '更新日：2026/07/01',
      );
      expect(formatFreshnessCaption(), '対象バージョン不明');
    });
  });

  test(
    'parses structured weapons/artifacts and ignores confidence for priority',
    () {
      final parsed = parseBuildRecommendation(structuredRecommendationJson());

      expect(parsed.investmentPriority, InvestmentPriority.high);
      expect(parsed.overallConfidence, 0.9);
      // confidence が高くても priority フィールドなしなら none
      final noPriority = parseBuildRecommendation({
        ...structuredRecommendationJson(),
        'investmentPriority': null,
        'context': {'role': 'dps'},
        'overallConfidence': 0.99,
      });
      expect(noPriority.investmentPriority, InvestmentPriority.none);

      expect(parsed.weapons, hasLength(2));
      expect(parsed.weapons.first.weaponId, 'w1');
      expect(parsed.weapons.first.reason, contains('HP'));
      expect(parsed.weapons.first.citation?.channelName, 'Sample Channel');
      // structured があるので legacy 文字列は使わない
      expect(parsed.youtubeWeapons.first.isLegacy, isFalse);
      expect(parsed.youtubeWeapons.first.displayName, '護摩の杖');

      expect(parsed.artifactRecommendations, hasLength(2));
      expect(parsed.artifactRecommendations.first.sets.single.pieces, 4);
      expect(parsed.artifactRecommendations[1].sets, hasLength(2));
      expect(parsed.artifactRecommendations[1].sets.map((e) => e.pieces), [
        2,
        2,
      ]);
      expect(parsed.artifactRecommendations[1].isAlternative, isTrue);

      expect(parsed.mainStats, hasLength(3));
      expect(parsed.freshnessCaption, contains('Ver.5.8'));
    },
  );

  test('ratio in recommendedStats does not crash and keeps other targets', () {
    final parsed = parseBuildRecommendation({
      ...structuredRecommendationJson(),
      'targets': <Object?>[],
      'recommendedStats': [
        {
          'stat': 'er',
          'valueType': 'minimum',
          'minimum': 180,
          'unit': 'percent',
        },
        {
          'stat': 'critRate',
          'valueType': 'ratio',
          'leftStat': 'critRate',
          'leftValue': 1,
          'rightStat': 'critDmg',
          'rightValue': 2,
          'unit': 'percent',
        },
        {
          'stat': 'em',
          'valueType': 'target',
          'recommended': 800,
          'unit': 'flat',
        },
      ],
    });
    expect(parsed.targets.map((t) => t.stat.name), containsAll(['er', 'em']));
    // ratio 行もクラッシュせずパースされる（表示は未対応でも min/max/recommended が null で保持）
    expect(parsed.targets.any((t) => t.stat.name == 'critRate'), isTrue);
  });

  test('legacy weaponPreference only when weapons missing', () {
    final parsed = parseBuildRecommendation({
      'characterId': 'x',
      'label': 't',
      'origin': 'single_video',
      'overallConfidence': 0.1,
      'context': {'weaponPreference': 'A、B'},
      'mainStats': <Object?>[],
      'substatPriority': <Object?>[],
      'targets': <Object?>[],
      'caveats': <Object?>[],
      'sources': <Object?>[],
      'evidence': <Object?>[],
    });
    expect(parsed.weapons, isEmpty);
    expect(parsed.youtubeWeapons.map((e) => e.displayName), ['A', 'B']);
    expect(parsed.youtubeWeapons.every((e) => e.isLegacy), isTrue);
  });
}
