import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/planning/build_growth_route_request.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';

void main() {
  test('uses related goal ids instead of synthetic daily item ids', () {
    final plan = DailyPlan(
      userId: 'user',
      date: DateTime(2026, 7, 15),
      items: const [
        DailyPlanItem(
          id: 'pri_goal-a',
          type: DailyPlanItemType.growthGoal,
          title: 'A',
          relatedGoalId: 'goal-a',
        ),
        DailyPlanItem(
          id: 'gen_goal-a',
          type: DailyPlanItemType.generalMaterial,
          title: 'A duplicate',
          relatedGoalId: 'goal-a',
        ),
        DailyPlanItem(
          id: 'pri_goal-b',
          type: DailyPlanItemType.growthGoal,
          title: 'B',
          relatedGoalId: 'goal-b',
        ),
      ],
    );

    final request = buildGrowthRouteRequest(
      plan,
      DateTime(2026, 7, 15, 23, 59),
    );

    expect(request.goalIds, ['goal-a', 'goal-b']);
    expect(request.startDate, DateTime(2026, 7, 15));
    expect(request.startWeekday, DateTime(2026, 7, 15).weekday);
  });
}
