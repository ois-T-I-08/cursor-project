import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/domain/account/account_snapshot.dart';
import 'package:genshin_builder_mobile/domain/account/account_health_report.dart';
import 'package:genshin_builder_mobile/domain/history/growth_event.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_goal.dart';
import 'package:genshin_builder_mobile/domain/planning/investment_diagnosis.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';
import 'package:genshin_builder_mobile/domain/team/team_models.dart';
import 'package:genshin_builder_mobile/application/planning/apply_daily_plan_enrichment.dart';
import 'package:genshin_builder_mobile/application/planning/generate_daily_plan_use_case.dart';
import 'package:genshin_builder_mobile/application/planning/diagnose_investment_use_case.dart';
import 'package:genshin_builder_mobile/application/history/detect_growth_events_use_case.dart';
import 'package:genshin_builder_mobile/application/account/generate_health_report_use_case.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_proposal.dart';

// Test helper: build a minimal AccountSnapshot
AccountSnapshot _testSnapshot({
  List<CharacterSnapshot> characters = const [],
  List<GrowthGoal> goals = const [],
  int? currentResin,
}) {
  return AccountSnapshot(
    userId: 'test',
    characters: characters,
    activeGoals: goals,
    currentResin: currentResin,
    maxResin: currentResin != null ? 200 : null,
    weekday: DateTime.now().weekday,
    acquiredAt: DateTime.now(),
    sources: ['test'],
  );
}

CharacterSnapshot _testChar(
  String id, {
  int level = 1,
  int weaponLevel = 1,
  bool owned = true,
}) {
  return CharacterSnapshot(
    characterId: id,
    name: 'Test$id',
    element: 'pyro',
    weaponType: 'sword',
    rarity: 5,
    region: 'Mondstadt',
    isOwned: owned,
    level: level,
    weaponLevel: weaponLevel,
  );
}

void main() {
  group('Team validation', () {
    test('Team.validate rejects duplicate characters', () {
      const team = Team(
        id: 't1',
        name: 'Test',
        members: [
          TeamMemberSlot(characterId: '10000002', position: 0),
          TeamMemberSlot(characterId: '10000002', position: 1),
        ],
      );
      expect(Team.validate(team), isNotNull);
      expect(Team.validate(team)!, contains('Duplicate'));
    });

    test('Team.validate rejects too many members', () {
      final team = Team(
        id: 't1',
        name: 'Test',
        members: List.generate(
          5,
          (i) => TeamMemberSlot(characterId: 'id$i', position: i),
        ),
      );
      expect(Team.validate(team), isNotNull);
    });

    test('Team.validate accepts valid team', () {
      const team = Team(
        id: 't1',
        name: 'Test',
        members: [
          TeamMemberSlot(characterId: '10000002', position: 0),
          TeamMemberSlot(characterId: '10000096', position: 1),
        ],
      );
      expect(Team.validate(team), isNull);
    });

    test('Team.isFull returns true at 4 members', () {
      final team = Team(
        id: 't1',
        name: 'Test',
        members: List.generate(
          4,
          (i) => TeamMemberSlot(characterId: 'id$i', position: i),
        ),
      );
      expect(team.isFull, isTrue);
    });
  });

  group('AccountHealthReport', () {
    test('scoreToRating produces all ratings', () {
      expect(AccountHealthReport.scoreToRating(90), HealthRating.excellent);
      expect(AccountHealthReport.scoreToRating(70), HealthRating.good);
      expect(AccountHealthReport.scoreToRating(50), HealthRating.average);
      expect(AccountHealthReport.scoreToRating(20), HealthRating.poor);
      expect(AccountHealthReport.scoreToRating(-1), HealthRating.unknown);
    });
  });

  group('GenerateDailyPlanUseCase', () {
    test('empty snapshot produces empty plan', () {
      final snapshot = _testSnapshot();
      final plan = const GenerateDailyPlanUseCase()(
        userId: 'test',
        snapshot: snapshot,
        date: DateTime(2026, 7, 14),
        weekday: 2,
      );
      expect(plan.items, isEmpty);
    });

    test('snapshot with goals produces items', () {
      const goal = GrowthGoal(
        id: 'g1',
        userId: 'test',
        characterId: '10000002',
        targetLevel: 90,
        status: GrowthGoalStatus.active,
      );
      final snapshot = _testSnapshot(goals: [goal], currentResin: 100);
      final plan = const GenerateDailyPlanUseCase()(
        userId: 'test',
        snapshot: snapshot,
        date: DateTime(2026, 7, 14),
        weekday: 2,
      );
      expect(plan.items, isNotEmpty);
      expect(plan.currentResin, 100);
    });

    test('topItems returns at most 3', () {
      final goals = List.generate(
        5,
        (i) => GrowthGoal(
          id: 'g$i',
          userId: 'test',
          characterId: 'id$i',
          targetLevel: 80 + i,
          status: GrowthGoalStatus.active,
        ),
      );
      final snapshot = _testSnapshot(goals: goals);
      final plan = const GenerateDailyPlanUseCase()(
        userId: 'test',
        snapshot: snapshot,
        date: DateTime(2026, 7, 14),
        weekday: 2,
      );
      expect(plan.topItems.length, lessThanOrEqualTo(3));
    });

    test('weekday materials become high-priority items', () {
      const materialsPlan = DailyMaterialsPlan(
        weekday: 2,
        talentCards: [
          DailyMaterialSeriesCardData(
            series: DailyMaterialSeries(
              id: 'freedom',
              name: '「自由」',
              region: 'Mondstadt',
              kind: DailyMaterialKind.talentBook,
              days: [2, 5],
              materialIds: ['m1'],
            ),
            materials: [
              MasterMaterial(
                id: 'm1',
                name: '「自由」の導き',
                category: 'talent',
                iconUrl: '',
              ),
            ],
            consumerGroups: [
              DailyMaterialConsumerGroup(
                key: 'chars',
                label: 'キャラ',
                consumers: [
                  DailyMaterialConsumer(
                    id: '10000002',
                    name: 'Ayaka',
                    remainingStatus: DailyRemainingStatus.needed,
                    remainingCount: 12,
                    remainingByMaterialId: {'m1': 12},
                  ),
                ],
              ),
            ],
            remainingByMaterialId: {'m1': 12},
            nextStageByMaterialId: {'m1': 3},
          ),
        ],
        weaponCards: [],
      );
      final plan = const GenerateDailyPlanUseCase()(
        userId: 'test',
        snapshot: _testSnapshot(),
        date: DateTime(2026, 7, 14),
        weekday: 2,
        materialsPlan: materialsPlan,
      );
      expect(plan.items, isNotEmpty);
      expect(plan.items.first.type, DailyPlanItemType.weekdayMaterial);
      expect(plan.items.first.characterIds, contains('10000002'));
      expect(plan.ruleVersion, '3');
    });
  });

  group('applyDailyPlanProposal', () {
    test('reorders and overrides reasons for allowlisted ids', () {
      final plan = DailyPlan(
        userId: 'test',
        date: DateTime(2026, 7, 14),
        ruleVersion: '2',
        items: const [
          DailyPlanItem(
            id: 'a',
            type: DailyPlanItemType.weekdayMaterial,
            title: 'A',
            priority: 90,
            reasons: ['local-a'],
          ),
          DailyPlanItem(
            id: 'b',
            type: DailyPlanItemType.weeklyBoss,
            title: 'B',
            priority: 85,
            reasons: ['local-b'],
          ),
        ],
      );
      final next = applyDailyPlanProposal(
        plan,
        DailyPlanProposal(
          summary: '週ボスを優先',
          recommendations: const [
            DailyPlanRecommendation(
              taskId: 'b',
              priority: 1,
              reason: '樹脂に余裕があるので週ボス',
              suggestedMinutes: 30,
            ),
            DailyPlanRecommendation(
              taskId: 'invented',
              priority: 2,
              reason: '無視される候補',
              suggestedMinutes: 20,
            ),
          ],
          deferredTaskIds: const [],
          warnings: const [],
          source: DailyPlanRecommendationSource.deepseek,
          generatedAt: DateTime(2026, 7, 14),
          inputHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          modelIdentifier: 'deepseek-v4-flash',
        ),
      );
      expect(next.items.map((e) => e.id).toList(), ['b', 'a']);
      expect(next.items.first.reasons.first, contains('週ボス'));
      expect(next.ruleVersion, '2+ai');
    });

    test('ignores enrichment when not enriched', () {
      final plan = DailyPlan(
        userId: 'test',
        date: DateTime(2026, 7, 14),
        items: const [
          DailyPlanItem(
            id: 'a',
            type: DailyPlanItemType.growthGoal,
            title: 'A',
          ),
        ],
      );
      final next = applyDailyPlanProposal(
        plan,
        DailyPlanProposal(
          summary: '候補なし',
          recommendations: const [],
          deferredTaskIds: const ['a'],
          warnings: const [],
          source: DailyPlanRecommendationSource.deterministicFallback,
          generatedAt: DateTime(2026, 7, 14),
          inputHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      );
      expect(
        identical(next, plan) || next.ruleVersion == plan.ruleVersion,
        isTrue,
      );
      expect(next.items.single.id, 'a');
    });
  });

  group('DiagnoseCharacterInvestmentUseCase', () {
    test('unowned character returns empty diagnosis', () {
      final char = _testChar('10000002', owned: false);
      final snapshot = _testSnapshot(characters: [char]);
      final diag = const DiagnoseCharacterInvestmentUseCase()(
        snapshot: snapshot,
        characterId: '10000002',
      );
      expect(diag.findings, isEmpty);
    });

    test('level below goal produces finding', () {
      final char = _testChar('10000002', level: 1);
      const goal = GrowthGoal(
        id: 'g1',
        userId: 'test',
        characterId: '10000002',
        targetLevel: 90,
        status: GrowthGoalStatus.active,
      );
      final snapshot = _testSnapshot(characters: [char], goals: [goal]);
      final diag = const DiagnoseCharacterInvestmentUseCase()(
        snapshot: snapshot,
        characterId: '10000002',
      );
      expect(diag.findings, isNotEmpty);
      final f = diag.findings.firstWhere(
        (f) => f.type == DiagnosisType.levelBelowGoal,
      );
      expect(f.currentValue, '1');
      expect(f.targetValue, '90');
    });

    test('weapon level low vs character level produces finding', () {
      final char = _testChar('10000002', level: 80, weaponLevel: 1);
      final snapshot = _testSnapshot(characters: [char]);
      final diag = const DiagnoseCharacterInvestmentUseCase()(
        snapshot: snapshot,
        characterId: '10000002',
      );
      final f = diag.findings.where(
        (f) => f.type == DiagnosisType.weaponLevelLowVsCharacter,
      );
      expect(f, isNotEmpty);
    });

    test('artifact unset produces info finding', () {
      final char = _testChar('10000002');
      final snapshot = _testSnapshot(characters: [char]);
      final diag = const DiagnoseCharacterInvestmentUseCase()(
        snapshot: snapshot,
        characterId: '10000002',
      );
      final f = diag.findings.where(
        (f) => f.type == DiagnosisType.artifactCompletionUnset,
      );
      expect(f, isNotEmpty);
    });
  });

  group('DetectGrowthEventsUseCase', () {
    test('isInitialSync produces no events', () {
      final before = [_testChar('10000002', level: 1)];
      final after = [_testChar('10000002', level: 90)];
      final events = const DetectGrowthEventsUseCase()(
        before: before,
        after: after,
        userId: 'test',
        isInitialSync: true,
      );
      expect(events, isEmpty);
    });

    test('no changes produces no events', () {
      final before = [_testChar('10000002', level: 80)];
      final after = [_testChar('10000002', level: 80)];
      final events = const DetectGrowthEventsUseCase()(
        before: before,
        after: after,
        userId: 'test',
      );
      expect(events, isEmpty);
    });

    test('level change produces event', () {
      final before = [_testChar('10000002', level: 1)];
      final after = [_testChar('10000002', level: 90)];
      final events = const DetectGrowthEventsUseCase()(
        before: before,
        after: after,
        userId: 'test',
      );
      expect(events.length, 1);
      expect(events.first.eventType, GrowthEventType.characterLevelChanged);
    });

    test('same change produces stable dedupKey', () {
      final before = [_testChar('10000002', level: 1)];
      final after = [_testChar('10000002', level: 90)];
      final events1 = const DetectGrowthEventsUseCase()(
        before: before,
        after: after,
        userId: 'test',
      );
      final events2 = const DetectGrowthEventsUseCase()(
        before: before,
        after: after,
        userId: 'test',
      );
      expect(events1.first.dedupKey, events2.first.dedupKey);
    });

    test('empty before produces no events', () {
      final after = [_testChar('10000002', level: 90)];
      final events = const DetectGrowthEventsUseCase()(
        before: [],
        after: after,
        userId: 'test',
      );
      expect(events, isEmpty);
    });
  });

  group('GenerateAccountHealthReportUseCase', () {
    test('empty snapshot produces report with no evaluated categories', () {
      final snapshot = _testSnapshot();
      final report = const GenerateAccountHealthReportUseCase()(
        snapshot: snapshot,
      );
      expect(report.categories, isNotEmpty);
      expect(report.totalScore, isNull); // no chars = nothing evaluable
      expect(report.isEvaluable, isFalse);
    });

    test('owned characters produce level score', () {
      final chars = List.generate(4, (i) => _testChar('id$i', level: 80 + i));
      final snapshot = _testSnapshot(characters: chars);
      final report = const GenerateAccountHealthReportUseCase()(
        snapshot: snapshot,
      );
      final levelCat = report.categories.firstWhere((c) => c.name == 'キャラレベル');
      expect(levelCat.evaluated, isTrue);
    });

    test('report has 5 health categories (data coverage separate)', () {
      final snapshot = _testSnapshot();
      final report = const GenerateAccountHealthReportUseCase()(
        snapshot: snapshot,
      );
      expect(report.categories.length, 5); // No Data Completeness in score
    });

    test('dataCoverage is available', () {
      final snapshot = _testSnapshot();
      final report = const GenerateAccountHealthReportUseCase()(
        snapshot: snapshot,
      );
      expect(report.dataCoverage, isNotEmpty);
    });
  });

  group('UpgradeOption', () {
    test('UpgradeOption fields are accessible', () {
      const opt = UpgradeOption(
        optionId: 'opt1',
        characterId: '10000002',
        optionType: 'level',
        fromValue: 1,
        toValue: 90,
        priority: 1,
      );
      expect(opt.characterId, '10000002');
      expect(opt.priority, 1);
    });

    test('UpgradeImpact stores effect', () {
      const impact = UpgradeImpact(
        impactScore: 0.064,
        affectedAreas: ['singleTarget'],
      );
      expect(impact.impactScore, 0.064);
      expect(impact.affectedAreas.first, 'singleTarget');
    });
  });
}
