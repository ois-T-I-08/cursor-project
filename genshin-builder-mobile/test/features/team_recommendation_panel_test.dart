import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';
import 'package:genshin_builder_mobile/features/teams/team_recommendation_panel.dart';
import 'package:genshin_builder_mobile/providers/app_providers.dart';
import 'package:genshin_builder_mobile/providers/team_recommendation_providers.dart';

void main() {
  testWidgets('shows theoretical value warning and credits', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [charactersProvider.overrideWith((ref) async => [])],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeamRecommendationPanel(attackerId: '10000089'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('シミュレーション結果は理論値です'), findsOneWidget);
    expect(find.textContaining('gcsim'), findsWidgets);
    expect(find.textContaining('AZA.GG'), findsWidgets);
    expect(find.text('所持キャラのみ'), findsOneWidget);
  });

  testWidgets('recommendation card shows stale, quality and alternatives', (
    tester,
  ) async {
    const recommendation = TeamRecommendation(
      members: ['10000089', '10000087', '10000025', '10000054'],
      score: 0.92,
      estimatedDps: 78543.2,
      simulationStatus: 'simulated',
      sourceTypes: ['aza', 'gcsim'],
      rotationConfidence: 'medium',
      observedByAza: true,
      isCached: true,
      isStale: true,
      inputQuality: SimulationInputQuality.partial,
      reasons: ['前回の正常値'],
      alternatives: {
        '10000054': ['10000032'],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamRecommendationCard(
              recommendation: recommendation,
              names: {
                '10000089': 'フリーナ',
                '10000087': 'ヌヴィレット',
                '10000025': '行秋',
                '10000054': '珊瑚宮心海',
                '10000032': 'ベネット',
              },
              generatedAt: DateTime(2026, 7, 20),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('推定DPS: 78543'), findsOneWidget);
    expect(find.textContaining('前回値'), findsOneWidget);
    expect(find.textContaining('入力品質: partial'), findsOneWidget);
    expect(find.textContaining('ベネット'), findsOneWidget);
  });

  testWidgets('disables a second calculation while a job is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          charactersProvider.overrideWith((ref) async => []),
          teamRecommendationControllerProvider(
            '10000089',
          ).overrideWith((ref) => _BusyController(ref)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeamRecommendationPanel(attackerId: '10000089'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'おすすめ編成を計算'),
    );
    expect(button.onPressed, isNull);
  });
}

class _BusyController extends TeamRecommendationController {
  _BusyController(Ref ref) : super(ref, '10000089') {
    state = const AsyncValue.data(
      TeamSimulationJob(
        jobId: '123e4567-e89b-42d3-a456-426614174000',
        status: TeamSimulationJobStatus.running,
      ),
    );
  }
}
