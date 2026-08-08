import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/planning/build_deterministic_daily_plan_proposal.dart';
import 'package:genshin_builder_mobile/application/planning/daily_plan_fingerprint.dart';
import 'package:genshin_builder_mobile/application/planning/generate_daily_plan_use_case.dart';
import 'package:genshin_builder_mobile/domain/account/account_snapshot.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_goal.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';

void main() {
  const character = CharacterSnapshot(
    characterId: '10000002',
    name: '神里綾華',
    element: 'cryo',
    weaponType: 'sword',
    rarity: 5,
    region: 'Inazuma',
    isOwned: true,
    talentSkill: 6,
  );

  test(
    'reuses upgrade option IDs and exposes only structured candidate facts',
    () {
      const option = UpgradeOption(
        optionId: 'goal-1_talentSkill',
        characterId: '10000002',
        optionType: 'talentSkill',
        relatedGoalId: 'goal-1',
        fromValue: 6,
        toValue: 9,
        remainingMaterials: {'104301': 9},
        estimatedResinCost: 40,
        priority: 4,
      );
      final plan = const GenerateDailyPlanUseCase()(
        userId: 'user',
        snapshot: const AccountSnapshot(
          userId: 'user',
          characters: [character],
        ),
        date: DateTime(2026, 8, 2),
        weekday: 7,
        upgradeOptions: [option],
        weekdayLimitedMaterialIds: {'104301'},
        availableMaterialIdsToday: {},
        bookmarkedCharacterIds: {'10000002'},
      );

      final item = plan.items.single;
      expect(item.id, option.optionId);
      expect(item.type, DailyPlanItemType.talent);
      expect(item.currentLevel, 6);
      expect(item.targetLevel, 9);
      expect(item.availableToday, isFalse);
      expect(item.bookmarked, isTrue);
      expect(item.reasons, isNotEmpty);
    },
  );

  test('candidate extraction is deterministically capped at 20', () {
    final goals = List.generate(
      25,
      (index) => GrowthGoal(
        id: 'goal-$index',
        userId: 'user',
        characterId: 'char-$index',
        targetLevel: 90,
        priority: index % 5,
      ),
    );
    final plan = const GenerateDailyPlanUseCase()(
      userId: 'user',
      snapshot: AccountSnapshot(userId: 'user', activeGoals: goals),
      date: DateTime(2026, 8, 2),
      weekday: 7,
    );
    expect(plan.items, hasLength(20));
    expect(plan.items.map((item) => item.id).toSet(), hasLength(20));
  });

  test(
    'local fallback enforces availability, resin, and invalidation fingerprint',
    () {
      final plan = DailyPlan(
        userId: 'user',
        date: DateTime(2026, 8, 2),
        currentResin: 20,
        availableMinutes: 30,
        items: const [
          DailyPlanItem(
            id: 'a',
            type: DailyPlanItemType.weekdayMaterial,
            title: 'A',
            priority: 100,
            estimatedResinCost: 20,
            estimatedMinutes: 20,
            requiresResin: true,
            reasons: ['今日開放'],
          ),
          DailyPlanItem(
            id: 'b',
            type: DailyPlanItemType.talent,
            title: 'B',
            priority: 90,
            estimatedResinCost: 20,
            estimatedMinutes: 20,
            requiresResin: true,
            reasons: ['目標との差3'],
          ),
          DailyPlanItem(
            id: 'c',
            type: DailyPlanItemType.talent,
            title: 'C',
            priority: 80,
            availableToday: false,
            reasons: ['本日は入手不可'],
          ),
        ],
      );
      final proposal = buildDeterministicDailyPlanProposal(plan);
      expect(proposal.recommendations.map((item) => item.taskId), ['a']);
      expect(proposal.deferredTaskIds, containsAll(['b', 'c']));
      expect(
        dailyPlanFingerprint(plan),
        isNot(
          dailyPlanFingerprint(
            plan.copyWith(
              items: [
                plan.items.first.copyWith(priority: 99),
                ...plan.items.skip(1),
              ],
            ),
          ),
        ),
      );
    },
  );
}
