import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/akasha/akasha_weapon_usage.dart';
import 'package:genshin_builder_mobile/domain/artifacts/character_recommended_artifact_sets.dart';
import 'package:genshin_builder_mobile/domain/build_recommendations/build_recommendation.dart';
import 'package:genshin_builder_mobile/domain/models/amber_detail_models.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/features/characters/widgets/character_artifact_insights_section.dart';
import 'package:genshin_builder_mobile/features/characters/widgets/character_detail_header.dart';
import 'package:genshin_builder_mobile/features/characters/widgets/character_weapon_insights_section.dart';
import 'package:genshin_builder_mobile/features/characters/widgets/guide_main_stats_panel.dart';
import 'package:genshin_builder_mobile/features/characters/widgets/recommended_stats_card.dart';
import 'package:genshin_builder_mobile/providers/build_recommendation_providers.dart';
import 'package:genshin_builder_mobile/providers/character_detail_providers.dart';

import '../fixtures/build_recommendation_fixtures.dart';

const _character = MasterCharacter(
  id: '10000046',
  name: 'とても長いキャラクター名テスト用胡桃',
  element: 'Pyro',
  weaponType: 'Polearm',
  rarity: 5,
  region: 'Liyue',
  iconUrl: '',
);

const _weapons = [
  MasterWeapon(
    id: 'w1',
    name: '護摩の杖',
    weaponType: 'Polearm',
    rarity: 5,
    iconUrl: '',
  ),
  MasterWeapon(
    id: 'w2',
    name: '非常に長い武器名を持つ試作・星鎌・テスト用',
    weaponType: 'Polearm',
    rarity: 4,
    iconUrl: '',
  ),
  MasterWeapon(
    id: 'w3',
    name: '匣中滅龍',
    weaponType: 'Polearm',
    rarity: 4,
    iconUrl: '',
  ),
  MasterWeapon(
    id: 'w4',
    name: '西風長槍',
    weaponType: 'Polearm',
    rarity: 4,
    iconUrl: '',
  ),
];

WeaponUsageSnapshot _akashaSnap({
  Map<String, double> rates = const {'w1': 0.4, 'w2': 0.2},
}) {
  return WeaponUsageSnapshot(
    characterId: _character.id,
    rates: rates,
    sampleSize: 100,
    source: 'akasha.cv',
    fetchedAt: DateTime.utc(2026, 7, 1),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  double width = 390,
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CharacterDetailHeader priority', () {
    testWidgets('long name + constellation + priority high', (tester) async {
      await _pump(
        tester,
        width: 320,
        textScale: 1.3,
        overrides: [
          avatarDetailProvider(_character.id).overrideWith((ref) async => null),
          buildRecommendationProvider(_character.id).overrideWith(
            (ref) async => buildRecommendationFixture(
              investmentPriority: InvestmentPriority.high,
            ),
          ),
        ],
        child: const CharacterDetailHeader(
          character: _character,
          level: 90,
          constellation: 6,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('とても長いキャラクター名'), findsOneWidget);
      expect(find.textContaining('凸6'), findsOneWidget);
      expect(find.text('高'), findsWidgets);
      expect(find.text('育成優先度'), findsOneWidget);
    });

    testWidgets('priority none when missing', (tester) async {
      await _pump(
        tester,
        overrides: [
          avatarDetailProvider(_character.id).overrideWith((ref) async => null),
          buildRecommendationProvider(_character.id).overrideWith(
            (ref) async => buildRecommendationFixture(
              investmentPriority: InvestmentPriority.none,
            ),
          ),
        ],
        child: const CharacterDetailHeader(
          character: _character,
          level: 80,
          constellation: 0,
        ),
      );

      expect(find.text('データなし'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CharacterWeaponInsightsView', () {
    testWidgets('Akasha only', (tester) async {
      await _pump(
        tester,
        child: CharacterWeaponInsightsView(
          weapons: _weapons,
          akashaAsync: AsyncValue.data(_akashaSnap()),
          guideAsync: const AsyncValue.data(null),
        ),
      );
      expect(find.textContaining('使用率'), findsWidgets);
      expect(find.text('護摩の杖'), findsOneWidget);
      expect(find.textContaining('まだ登録されていません'), findsOneWidget);
    });

    testWidgets('YouTube only with expand', (tester) async {
      var expanded = false;
      final rec = buildRecommendationFixture(
        weapons: [
          for (var i = 1; i <= 4; i++)
            GuideWeaponRecommendation(
              weaponId: 'w$i',
              rank: i,
              reason: i == 1 ? '理由テキスト' : null,
              conditions: i == 1 ? const ['無凸時'] : const [],
            ),
        ],
      );

      await _pump(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return CharacterWeaponInsightsView(
              weapons: _weapons,
              akashaAsync: AsyncValue.data(
                WeaponUsageSnapshot(
                  characterId: _character.id,
                  rates: const {},
                  sampleSize: 0,
                  source: 'heuristic',
                  fetchedAt: DateTime.utc(2026, 7, 1),
                ),
              ),
              guideAsync: AsyncValue.data(rec),
              youtubeExpanded: expanded,
              onToggleYoutubeExpand: () => setState(() => expanded = !expanded),
            );
          },
        ),
      );

      expect(find.text('護摩の杖'), findsOneWidget);
      expect(find.textContaining('理由テキスト'), findsOneWidget);
      expect(find.textContaining('無凸時'), findsOneWidget);
      expect(find.textContaining('残り 1 件を表示'), findsOneWidget);
      await tester.tap(find.textContaining('残り 1 件を表示'));
      await tester.pumpAndSettle();
      expect(find.text('西風長槍'), findsOneWidget);
    });

    testWidgets('both sources and shared weapon', (tester) async {
      await _pump(
        tester,
        child: CharacterWeaponInsightsView(
          weapons: _weapons,
          akashaAsync: AsyncValue.data(_akashaSnap(rates: const {'w1': 0.5})),
          guideAsync: AsyncValue.data(
            buildRecommendationFixture(
              weapons: const [
                GuideWeaponRecommendation(weaponId: 'w1', rank: 1),
              ],
            ),
          ),
        ),
      );
      expect(find.text('護摩の杖'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('both empty', (tester) async {
      await _pump(
        tester,
        child: CharacterWeaponInsightsView(
          weapons: _weapons,
          akashaAsync: AsyncValue.data(
            WeaponUsageSnapshot(
              characterId: _character.id,
              rates: const {},
              sampleSize: 0,
              source: 'heuristic',
              fetchedAt: DateTime.utc(2026, 7, 1),
            ),
          ),
          guideAsync: AsyncValue.data(
            buildRecommendationFixture(weapons: const []),
          ),
        ),
      );
      expect(find.textContaining('使用率データがありません'), findsOneWidget);
      expect(find.textContaining('おすすめ武器はまだ登録されていません'), findsOneWidget);
    });

    testWidgets('long weapon name no overflow', (tester) async {
      await _pump(
        tester,
        width: 300,
        textScale: 1.4,
        child: CharacterWeaponInsightsView(
          weapons: _weapons,
          akashaAsync: AsyncValue.data(
            WeaponUsageSnapshot(
              characterId: _character.id,
              rates: const {},
              sampleSize: 0,
              source: 'heuristic',
              fetchedAt: DateTime.utc(2026, 7, 1),
            ),
          ),
          guideAsync: AsyncValue.data(
            buildRecommendationFixture(
              weapons: const [
                GuideWeaponRecommendation(weaponId: 'w2', rank: 1),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('非常に長い武器名'), findsOneWidget);
    });
  });

  group('CharacterArtifactInsightsView', () {
    const catalog = [
      ArtifactSetDetail(
        id: '15020',
        name: '絶縁の旗印',
        iconUrl: null,
        effects: ['2セット', '4セット'],
      ),
      ArtifactSetDetail(
        id: '15017',
        name: '追憶のしめ縄',
        iconUrl: null,
        effects: [],
      ),
      ArtifactSetDetail(
        id: '15008',
        name: '剣闘士のフィナーレ',
        iconUrl: null,
        effects: [],
      ),
    ];

    testWidgets('4-piece and 2+2 youtube sets', (tester) async {
      final rec = buildRecommendationFixture(
        artifactRecommendations: const [
          GuideArtifactRecommendation(
            sets: [GuideArtifactSetPart(setId: '15020', pieces: 4)],
            rank: 1,
            reason: '長い推奨理由を表示するためのテスト文字列です。状況によって最適解は変わります。',
          ),
          GuideArtifactRecommendation(
            sets: [
              GuideArtifactSetPart(setId: '15017', pieces: 2),
              GuideArtifactSetPart(setId: '15008', pieces: 2),
            ],
            rank: 2,
            isAlternative: true,
          ),
        ],
        mainStats: const [],
      );

      await _pump(
        tester,
        child: CharacterArtifactInsightsView(
          akashaAsync: const AsyncValue.data([]),
          guideAsync: AsyncValue.data(rec),
          artifactSets: catalog,
        ),
      );

      expect(find.textContaining('絶縁の旗印 4セット'), findsOneWidget);
      expect(find.textContaining('追憶のしめ縄 2セット'), findsOneWidget);
      expect(find.textContaining('剣闘士のフィナーレ 2セット'), findsOneWidget);
      expect(find.textContaining('長い推奨理由'), findsOneWidget);
      expect(find.textContaining('代替候補'), findsOneWidget);
    });

    testWidgets('unknown set id is safe', (tester) async {
      await _pump(
        tester,
        child: CharacterArtifactInsightsView(
          akashaAsync: const AsyncValue.data([]),
          guideAsync: AsyncValue.data(
            buildRecommendationFixture(
              artifactRecommendations: const [
                GuideArtifactRecommendation(
                  sets: [GuideArtifactSetPart(setId: 'unknown', pieces: 4)],
                ),
              ],
              mainStats: const [],
            ),
          ),
          artifactSets: catalog,
        ),
      );
      expect(find.textContaining('未登録セット(unknown)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Akasha only and youtube empty', (tester) async {
      await _pump(
        tester,
        child: CharacterArtifactInsightsView(
          akashaAsync: AsyncValue.data([
            CharacterRecommendedArtifactSet(
              set: catalog.first,
              usageRate: 0.33,
              source: 'akasha',
            ),
          ]),
          guideAsync: AsyncValue.data(
            buildRecommendationFixture(
              artifactRecommendations: const [],
              mainStats: const [],
            ),
          ),
          artifactSets: catalog,
        ),
      );
      expect(find.text('絶縁の旗印'), findsOneWidget);
      expect(find.textContaining('おすすめ聖遺物セットはまだ登録されていません'), findsOneWidget);
    });
  });

  group('GuideMainStatsPanel', () {
    testWidgets('primary only / alternatives / conditions / partial slots', (
      tester,
    ) async {
      await _pump(
        tester,
        child: const GuideMainStatsPanel(
          mainStats: [
            GuideMainStatRecommendation(
              slot: GuideArtifactSlot.sands,
              candidates: ['元素熟知'],
            ),
            GuideMainStatRecommendation(
              slot: GuideArtifactSlot.goblet,
              candidates: ['炎元素ダメージ', '攻撃力%'],
              condition: 'サブステ差が大きい場合',
            ),
          ],
        ),
      );

      expect(find.text('時計'), findsOneWidget);
      expect(find.textContaining('第一候補: 元素熟知'), findsOneWidget);
      expect(find.textContaining('第一候補: 炎元素ダメージ'), findsOneWidget);
      expect(find.textContaining('代替候補: 攻撃力%'), findsOneWidget);
      expect(find.textContaining('条件: サブステ差'), findsOneWidget);
      expect(find.text('冠'), findsNothing);
    });

    testWidgets('empty main stats', (tester) async {
      await _pump(tester, child: const GuideMainStatsPanel(mainStats: []));
      expect(find.textContaining('まだ登録されていません'), findsOneWidget);
    });
  });

  group('RecommendedStatsCard states', () {
    testWidgets('section error offers retry without blocking the screen', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: [
          buildRecommendationProvider(_character.id).overrideWith(
            (ref) async =>
                throw const BuildRecommendationException(
                  BuildRecommendationFailure.networkError,
                ),
          ),
        ],
        child: RecommendedStatsCard(
          characterId: _character.id,
          currentStats: {},
        ),
      );

      expect(find.textContaining('取得できませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
