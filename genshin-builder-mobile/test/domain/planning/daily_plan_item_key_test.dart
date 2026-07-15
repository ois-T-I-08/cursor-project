import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_item_key.dart';

void main() {
  group('dailyPlanItemKey', () {
    test('is stable for identical semantic fields', () {
      const a = DailyPlanItem(
        id: 'random-a',
        type: DailyPlanItemType.growthGoal,
        title: 'Title A',
        relatedGoalId: 'goal-1',
        characterIds: ['c2', 'c1'],
        materialIds: ['m2', 'm1'],
      );
      const b = DailyPlanItem(
        id: 'random-b',
        type: DailyPlanItemType.growthGoal,
        title: 'Title B translated',
        relatedGoalId: 'goal-1',
        characterIds: ['c1', 'c2'],
        materialIds: ['m1', 'm2'],
      );
      expect(dailyPlanItemKey(a), dailyPlanItemKey(b));
      expect(
        dailyPlanItemKey(a),
        'v1|type=growthGoal|goal=goal-1|chars=c1,c2|mats=m1,m2',
      );
    });

    test('ignores title differences', () {
      const a = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.weekdayMaterial,
        title: '月曜素材',
        materialIds: ['mat'],
      );
      const b = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.weekdayMaterial,
        title: 'Monday mats',
        materialIds: ['mat'],
      );
      expect(dailyPlanItemKey(a), dailyPlanItemKey(b));
    });

    test('differs when type / goal / ids differ', () {
      const base = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.growthGoal,
        title: 'x',
        relatedGoalId: 'g1',
        characterIds: ['c1'],
      );
      const otherType = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.generalMaterial,
        title: 'x',
        relatedGoalId: 'g1',
        characterIds: ['c1'],
      );
      const otherGoal = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.growthGoal,
        title: 'x',
        relatedGoalId: 'g2',
        characterIds: ['c1'],
      );
      expect(dailyPlanItemKey(base), isNot(dailyPlanItemKey(otherType)));
      expect(dailyPlanItemKey(base), isNot(dailyPlanItemKey(otherGoal)));
    });

    test('empty goal and lists encode stably', () {
      const item = DailyPlanItem(
        id: '1',
        type: DailyPlanItemType.weeklyBoss,
        title: 'boss',
      );
      expect(
        dailyPlanItemKey(item),
        'v1|type=weeklyBoss|goal=|chars=|mats=',
      );
    });
  });

  test('formatLocalDate pads components', () {
    expect(formatLocalDate(DateTime(2026, 7, 5)), '2026-07-05');
  });
}
