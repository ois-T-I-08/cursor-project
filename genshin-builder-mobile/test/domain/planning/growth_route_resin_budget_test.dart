import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/planning/build_growth_route_request.dart';
import 'package:genshin_builder_mobile/application/planning/optimize_growth_route_use_case.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';

void main() {
  group('buildGrowthRouteRequest', () {
    test('uses maxResin when present', () {
      final req = buildGrowthRouteRequest(
        DailyPlan(
          userId: 'u',
          date: DateTime(2026, 7, 15),
          maxResin: 200,
          items: const [
            DailyPlanItem(
              id: '1',
              type: DailyPlanItemType.growthGoal,
              title: 't',
              relatedGoalId: 'g1',
            ),
          ],
        ),
        DateTime(2026, 7, 15),
      );
      expect(req.dailyResinBudget, 200);
      expect(req.goalIds, ['g1']);
    });

    test('defaults to 160 when maxResin missing', () {
      final req = buildGrowthRouteRequest(
        DailyPlan(userId: 'u', date: DateTime(2026, 7, 15)),
        DateTime(2026, 7, 15),
      );
      expect(req.dailyResinBudget, kDefaultDailyResinBudget);
    });
  });

  group('OptimizeGrowthRouteUseCase resin display budget', () {
    test('does not enforce budget by default even when set', () {
      final options = [
        UpgradeOption(
          optionId: 'o1',
          characterId: 'c1',
          optionType: 'level',
          fromValue: 1,
          toValue: 90,
          priority: 2,
          estimatedResinCost: 200,
          calculationMode: CalculationMode.exactMasterData,
        ),
        UpgradeOption(
          optionId: 'o2',
          characterId: 'c1',
          optionType: 'level',
          fromValue: 1,
          toValue: 80,
          priority: 1,
          estimatedResinCost: 200,
          calculationMode: CalculationMode.exactMasterData,
        ),
      ];
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local',
        options: options,
        startDate: DateTime(2026, 7, 14),
        startWeekday: 1,
        dailyResinBudget: 200,
        enforceDailyResinBudget: false,
      );
      expect(route.dailyResinBudget, 200);
      expect(route.days.first.actions.length, 2);
      expect(route.totalEstimatedResin, 400);
    });

    test('enforceDailyResinBudget still limits when true', () {
      final options = [
        UpgradeOption(
          optionId: 'o1',
          characterId: 'c1',
          optionType: 'level',
          priority: 2,
          estimatedResinCost: 200,
          calculationMode: CalculationMode.exactMasterData,
        ),
        UpgradeOption(
          optionId: 'o2',
          characterId: 'c1',
          optionType: 'level',
          priority: 1,
          estimatedResinCost: 200,
          calculationMode: CalculationMode.exactMasterData,
        ),
      ];
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local',
        options: options,
        startDate: DateTime(2026, 7, 14),
        startWeekday: 1,
        dailyResinBudget: 200,
        enforceDailyResinBudget: true,
      );
      expect(route.days.first.actions.length, lessThanOrEqualTo(1));
    });
  });
}
