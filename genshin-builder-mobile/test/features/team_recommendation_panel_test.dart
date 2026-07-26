import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';
import 'package:genshin_builder_mobile/features/teams/team_recommendation_panel.dart';
import 'package:genshin_builder_mobile/providers/app_providers.dart';
import 'package:genshin_builder_mobile/providers/team_recommendation_providers.dart';

void main() {
  testWidgets('shows disclaimer and AZA credits', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          charactersProvider.overrideWith((ref) async => []),
          teamRecommendationControllerProvider(
            '10000089',
          ).overrideWith((ref) => _IdleController(ref)),
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
    await tester.pump();
    expect(find.textContaining('螺旋の使用実績と共通ルール'), findsOneWidget);
    expect(find.textContaining('gcsim'), findsNothing);
    expect(find.textContaining('AZA.GG'), findsWidgets);
    expect(find.text('所持キャラのみ'), findsOneWidget);
  });

  testWidgets('auto-starts recommendation when attacker is set', (tester) async {
    late _TrackingController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          charactersProvider.overrideWith((ref) async => []),
          teamRecommendationControllerProvider('10000089').overrideWith((ref) {
            controller = _TrackingController(ref);
            return controller;
          }),
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
    await tester.pump();
    expect(controller.startCount, 1);
  });

  testWidgets('recommendation card shows quality and alternatives', (
    tester,
  ) async {
    const recommendation = TeamRecommendation(
      members: ['10000089', '10000087', '10000025', '10000054'],
      score: 0.92,
      simulationStatus: 'observed',
      sourceTypes: ['aza'],
      rotationConfidence: 'medium',
      observedByAza: true,
      inputQuality: SimulationInputQuality.partial,
      reasons: ['AZA.GGの深境螺旋で使用実績があります'],
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
              onApply: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('推定DPS'), findsNothing);
    expect(find.textContaining('AZA.GG使用実績'), findsOneWidget);
    expect(find.textContaining('入力品質: partial'), findsOneWidget);
    expect(find.textContaining('ベネット'), findsOneWidget);
    expect(find.text('この編成を入れる'), findsOneWidget);
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
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '再計算'),
    );
    expect(button.onPressed, isNull);
  });
}

class _IdleController extends TeamRecommendationController {
  _IdleController(Ref ref) : super(ref, '10000089');

  @override
  Future<void> start(TeamRecommendationOptions options) async {}
}

class _TrackingController extends TeamRecommendationController {
  _TrackingController(Ref ref) : super(ref, '10000089');
  int startCount = 0;

  @override
  Future<void> start(TeamRecommendationOptions options) async {
    startCount += 1;
  }
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

  @override
  Future<void> start(TeamRecommendationOptions options) async {}
}
