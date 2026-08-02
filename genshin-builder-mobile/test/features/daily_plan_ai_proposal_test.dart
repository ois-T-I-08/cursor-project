import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_proposal.dart';
import 'package:genshin_builder_mobile/features/growth/daily_plan_screen.dart';
import 'package:genshin_builder_mobile/providers/daily_plan_completion_providers.dart';
import 'package:genshin_builder_mobile/providers/growth_providers.dart';

void main() {
  testWidgets(
    'shows AI source, top reason, adopt, regenerate, and close actions',
    (tester) async {
      final plan = DailyPlan(
        userId: 'user',
        date: DateTime(2026, 8, 2),
        items: const [
          DailyPlanItem(
            id: 'task_a',
            type: DailyPlanItemType.talent,
            title: '元素スキルをLv.9へ',
            priority: 95,
            reasons: ['今日開放'],
          ),
        ],
      );
      final proposal = DailyPlanProposal(
        summary: '今日は天賦素材を優先すると効率的です',
        recommendations: const [
          DailyPlanRecommendation(
            taskId: 'task_a',
            priority: 1,
            reason: '本日入手可能で、目標との差が大きいため',
            suggestedMinutes: 20,
          ),
        ],
        deferredTaskIds: const [],
        warnings: const [],
        source: DailyPlanRecommendationSource.deepseek,
        generatedAt: DateTime.utc(2026, 8, 2, 3),
        inputHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adoptedDailyPlanProvider.overrideWith((ref) async => plan),
            dailyPlanProposalProvider(0).overrideWith((ref) async => proposal),
            dailyPlanTodayCompletionsProvider.overrideWith(
              (ref) async => <String>{},
            ),
          ],
          child: const MaterialApp(home: DailyPlanScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AI提案'), findsOneWidget);
      expect(find.text(proposal.summary), findsOneWidget);
      expect(find.textContaining('目標との差が大きい'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '提案を採用'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '再生成'), findsOneWidget);

      await tester.tap(find.byTooltip('提案を閉じる'));
      await tester.pump();
      expect(find.text(proposal.summary), findsNothing);
    },
  );
}
