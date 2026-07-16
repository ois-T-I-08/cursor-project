import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_route_request.dart';
import 'package:genshin_builder_mobile/domain/team/team_models.dart';
import 'package:genshin_builder_mobile/domain/account/account_snapshot.dart';
import 'package:genshin_builder_mobile/application/planning/optimize_growth_route_use_case.dart';
import 'package:genshin_builder_mobile/application/planning/generate_team_growth_priority_use_case.dart';

final _testDate = DateTime(2026, 7, 15);

AccountSnapshot _testSnapshot(List<CharacterSnapshot> chars) => AccountSnapshot(
      userId: 'local', characters: chars,
      acquiredAt: _testDate, sources: ['test'],
    );

CharacterSnapshot _testChar(String id, {int level = 1, int weaponLevel = 1}) =>
    CharacterSnapshot(
      characterId: id, name: 'Test$id', element: 'pyro',
      weaponType: 'sword', rarity: 5, region: 'Mondstadt',
      isOwned: true, level: level, weaponLevel: weaponLevel,
    );

void main() {
  group('OptimizeGrowthRouteUseCase', () {
    test('empty options produces empty route', () {
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: [], startDate: _testDate, startWeekday: 3,
      );
      expect(route.days, isEmpty);
    });

    test('options produce scheduled days', () {
      final options = [
        const UpgradeOption(optionId: 'o1', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 80, priority: 2,
            calculationMode: CalculationMode.exactMasterData),
        const UpgradeOption(optionId: 'o2', characterId: 'c1', optionType: 'talentBurst',
            fromValue: 1, toValue: 8, priority: 1,
            calculationMode: CalculationMode.exactMasterData),
      ];
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
      );
      expect(route.days.isNotEmpty, isTrue);
      expect(route.goals.length, 2);
      expect(route.ruleVersion, '4');
    });

    test('same input produces same output', () {
      final options = [
        const UpgradeOption(optionId: 'o1', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 90, priority: 2,
            calculationMode: CalculationMode.exactMasterData),
      ];
      final route1 = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
      );
      final route2 = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
      );
      expect(route1.days.length, route2.days.length);
      expect(route1.days.map((d) => d.date).toList(), route2.days.map((d) => d.date).toList());
      expect(route1.unresolvedCosts, route2.unresolvedCosts);
      expect(route1.ruleVersion, route2.ruleVersion);
    });

    test('defaultDayCount is 7', () {
      expect(OptimizeGrowthRouteUseCase.defaultDayCount, 7);
    });

    test('options without inventory show low confidence', () {
      final options = [
        const UpgradeOption(optionId: 'o1', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 80,
            calculationMode: CalculationMode.estimatedInventoryMissing),
      ];
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
      );
      expect(route.confidence, isNotNull);
    });

    test('weekday-limited option placed on correct day', () {
      final options = [
        const UpgradeOption(optionId: 'tue', characterId: 'c1', optionType: 'talentNormal',
            fromValue: 1, toValue: 8, priority: 2,
            materialsCost: {'mat_tue': 3},
            calculationMode: CalculationMode.exactMasterData),
      ];
      final wkMap = {'mat_tue': {3}}; // material available on Wednesday

      final routeWed = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
        weekdayMap: wkMap,
      );
      // Wednesday is the first day, so it should be scheduled
      final wedActions = routeWed.days.isNotEmpty ? routeWed.days.first.actions : [];
      expect(wedActions.isNotEmpty, isTrue);

      // Monday: material not available
      final routeMon = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 1,
        weekdayMap: wkMap,
      );
      final monActions = routeMon.days.isNotEmpty ? routeMon.days.first.actions : [];
      final hasWeekdayItem = monActions.any((a) => a.actionType == 'weekdayMaterial');
      expect(hasWeekdayItem, isFalse);
    });

    test('daily budget respects resin limit', () {
      final options = [
        const UpgradeOption(optionId: 'o1', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 90, priority: 2,
            estimatedResinCost: 200,
            calculationMode: CalculationMode.exactMasterData),
        const UpgradeOption(optionId: 'o2', characterId: 'c1', optionType: 'talentBurst',
            fromValue: 1, toValue: 10, priority: 1,
            estimatedResinCost: 200,
            calculationMode: CalculationMode.exactMasterData),
      ];
      final route = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 1,
        dailyResinBudget: 200,
        enforceDailyResinBudget: true,
      );
      // One action per day with budget=200 and cost=200 each
      final firstDayCount = route.days.isNotEmpty ? route.days.first.actions.length : 0;
      expect(firstDayCount, lessThanOrEqualTo(1));
    });

    // ── Fix 1: weekday-limited items NOT placed on wrong days ────────

    test('weekday-limited item not placed on unavailable weekday as generalMaterial', () {
      final options = [
        const UpgradeOption(optionId: 'talent_tue', characterId: 'c1', optionType: 'talentNormal',
            fromValue: 1, toValue: 8, priority: 2,
            materialsCost: {'mat_tue_only': 3},
            calculationMode: CalculationMode.exactMasterData),
        const UpgradeOption(optionId: 'non_limited', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 10, priority: 1,
            materialsCost: {'mat_any': 2},
            calculationMode: CalculationMode.exactMasterData),
      ];
      final wkMap = {'mat_tue_only': {3}}; // only Wednesday

      // Monday (weekday=1) — talent should NOT appear
      final routeMon = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 1,
        weekdayMap: wkMap,
      );
      final monDay = routeMon.days.firstOrNull;
      expect(monDay, isNotNull);
      if (monDay != null) {
        final hasTalent = monDay.actions.any((a) => a.optionId == 'talent_tue');
        expect(hasTalent, isFalse,
            reason: 'Weekday-limited option must not appear as any action type on wrong day');
        // Non-limited item should appear
        final hasNonLimited = monDay.actions.any((a) => a.optionId == 'non_limited');
        expect(hasNonLimited, isTrue);
      }
    });

    test('weekday-limited item placed on correct weekday', () {
      final options = [
        const UpgradeOption(optionId: 'talent_tue', characterId: 'c1', optionType: 'talentNormal',
            fromValue: 1, toValue: 8, priority: 2,
            materialsCost: {'mat_tue_only': 3},
            calculationMode: CalculationMode.exactMasterData),
      ];
      final wkMap = {'mat_tue_only': {3}}; // Wednesday

      // Wednesday (weekday=3) — talent SHOULD appear
      final routeWed = const OptimizeGrowthRouteUseCase()(
        userId: 'local', options: options, startDate: _testDate, startWeekday: 3,
        weekdayMap: wkMap,
      );
      final wedDay = routeWed.days.firstOrNull;
      expect(wedDay, isNotNull);
      if (wedDay != null) {
        final hasTalent = wedDay.actions.any((a) => a.optionId == 'talent_tue');
        expect(hasTalent, isTrue);
      }
    });
  });

  group('GenerateTeamGrowthPriorityUseCase', () {
    test('empty team returns empty report', () {
      const team = Team(id: 't1', name: 'Test', members: []);
      final snapshot = _testSnapshot([]);
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: {},
      );
      expect(report.memberPriorities, isEmpty);
    });

    test('4 members ranked by score', () {
      final chars = List.generate(4, (i) => _testChar('id$i', level: 20 + i * 20));
      final snapshot = _testSnapshot(chars);
      final team = Team(
        id: 't1', name: 'Test',
        members: List.generate(4, (i) => TeamMemberSlot(characterId: 'id$i', position: i)),
      );
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: {},
      );
      expect(report.memberPriorities.length, 4);
      // Lower level = higher priority (since more issues)
      expect(report.memberPriorities.first.characterId, 'id0');
      expect(report.memberPriorities.first.displayName, 'Testid0');
    });

    test('member displayName uses snapshot character name', () {
      final chars = [
        const CharacterSnapshot(
          characterId: '10000052',
          name: '雷電将軍',
          element: 'electro',
          weaponType: 'polearm',
          rarity: 5,
          region: 'Inazuma',
          isOwned: true,
          level: 70,
        ),
      ];
      final snapshot = _testSnapshot(chars);
      const team = Team(
        id: 't1',
        name: 'Test',
        members: [TeamMemberSlot(characterId: '10000052', position: 0)],
      );
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team,
        snapshot: snapshot,
        upgradeOptionsByCharacter: {},
      );
      expect(report.memberPriorities.single.displayName, '雷電将軍');
    });

    test('characters with upgrade options get higher priority', () {
      final chars = [_testChar('c1', level: 80), _testChar('c2', level: 80)];
      final snapshot = _testSnapshot(chars);
      const team = Team(id: 't1', name: 'Test', members: [
        TeamMemberSlot(characterId: 'c1', position: 0),
        TeamMemberSlot(characterId: 'c2', position: 1),
      ]);
      final opts = {
        'c1': [
          const UpgradeOption(optionId: 'opt', characterId: 'c1', optionType: 'level',
            fromValue: 80, toValue: 90, priority: 2,
            calculationMode: CalculationMode.exactMasterData,
            impact: UpgradeImpact(impactScore: 0.3, impactBand: ImpactBand.high)),
        ],
      };
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: opts,
      );
      expect(report.memberPriorities.first.characterId, 'c1');
    });

    test('unowned character is deprioritized', () {
      final chars = [
        _testChar('c1', level: 80),
        const CharacterSnapshot(characterId: 'c2', name: 'Test2', element: 'pyro',
            weaponType: 'sword', rarity: 5, region: 'Mondstadt', isOwned: false),
      ];
      final snapshot = _testSnapshot(chars);
      const team = Team(id: 't1', name: 'Test', members: [
        TeamMemberSlot(characterId: 'c1', position: 0),
        TeamMemberSlot(characterId: 'c2', position: 1),
      ]);
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: {},
      );
      final unowned = report.memberPriorities.firstWhere((p) => p.characterId == 'c2');
      expect(unowned.priority, -1);
    });

    test('shared materials are detected', () {
      final chars = [_testChar('c1'), _testChar('c2')];
      final snapshot = _testSnapshot(chars);
      const team = Team(id: 't1', name: 'Test', members: [
        TeamMemberSlot(characterId: 'c1', position: 0),
        TeamMemberSlot(characterId: 'c2', position: 1),
      ]);
      final opts = {
        'c1': [
          const UpgradeOption(optionId: 's1', characterId: 'c1', optionType: 'level',
            fromValue: 1, toValue: 90, materialsCost: {'mat_x': 10},
            calculationMode: CalculationMode.exactMasterData),
        ],
        'c2': [
          const UpgradeOption(optionId: 's2', characterId: 'c2', optionType: 'level',
            fromValue: 1, toValue: 90, materialsCost: {'mat_x': 15},
            calculationMode: CalculationMode.exactMasterData),
        ],
      };
      final report = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: opts,
      );
      expect(report.sharedMaterialOpportunities, isNotEmpty);
    });

    test('deterministic output for same input', () {
      final chars = [_testChar('c1'), _testChar('c2')];
      final snapshot = _testSnapshot(chars);
      const team = Team(id: 't1', name: 'Test', members: [
        TeamMemberSlot(characterId: 'c1', position: 0),
        TeamMemberSlot(characterId: 'c2', position: 1),
      ]);
      final r1 = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: {},
      );
      final r2 = const GenerateTeamGrowthPriorityUseCase()(
        team: team, snapshot: snapshot, upgradeOptionsByCharacter: {},
      );
      expect(r1.memberPriorities.map((p) => p.characterId).toList(),
          r2.memberPriorities.map((p) => p.characterId).toList());
    });
  });

  // ── GrowthRouteRequest weekdayMap deep immutability ─────────────

  group('GrowthRouteRequest', () {
    // ── goalId immutability ────────────────────────────────────────

    test('goalIds is sorted, deduplicated, and immutable', () {
      final req = GrowthRouteRequest(
        goalIds: ['goal-a', 'goal-a', 'goal-b'],
        startDate: _testDate,
        startWeekday: 3,
      );
      expect(req.goalIds, ['goal-a', 'goal-b']);
      expect(() => (req.goalIds as List).add('new'), throwsUnsupportedError);
    });

    test('same goalIds different order are equal', () {
      final req1 = GrowthRouteRequest(
        goalIds: ['goal-b', 'goal-a'], startDate: _testDate, startWeekday: 3,
      );
      final req2 = GrowthRouteRequest(
        goalIds: ['goal-a', 'goal-b'], startDate: _testDate, startWeekday: 3,
      );
      expect(req1, req2);
      expect(req1.hashCode, req2.hashCode);
    });

    test('different goalIds are not equal', () {
      final req1 = GrowthRouteRequest(goalIds: ['goal-a'], startDate: _testDate, startWeekday: 3);
      final req2 = GrowthRouteRequest(goalIds: ['goal-b'], startDate: _testDate, startWeekday: 3);
      expect(req1, isNot(req2));
    });

    // ── weekdayMap immutability ────────────────────────────────────

    test('weekdayMap is not affected by source map mutation', () {
      final source = <String, Set<int>>{'material-a': {1, 4, 7}};
      final req = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: source,
      );
      source['material-b'] = {2, 5, 7};
      source.remove('material-a');

      expect(req.weekdayMap!.length, 1);
      expect(req.weekdayMap!['material-a'], {1, 4, 7});
      expect(req.weekdayMap!['material-b'], isNull);
    });

    test('weekdayMap is not affected by source set mutation', () {
      final days = <int>{1, 4, 7};
      final source = <String, Set<int>>{'material-a': days};
      final req = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: source,
      );
      days.clear();
      days.add(2);

      expect(req.weekdayMap!['material-a'], {1, 4, 7});
    });

    test('request weekdayMap cannot be mutated', () {
      final req = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'material-a': {1, 4}},
      );
      expect(
        () => (req.weekdayMap as Map)['material-b'] = {2},
        throwsUnsupportedError,
      );
    });

    test('request weekdayMap inner set cannot be mutated', () {
      final req = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'material-a': {1, 4}},
      );
      expect(
        () => req.weekdayMap!['material-a']!.add(2),
        throwsUnsupportedError,
      );
    });

    // ── weekdayMap equality ────────────────────────────────────────

    test('weekdayMap order-independent equality', () {
      final req1 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_a': {1, 4, 7}, 'mat_b': {2, 5, 7}},
      );
      final req2 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_b': {7, 5, 2}, 'mat_a': {7, 1, 4}},
      );
      expect(req1, req2);
      expect(req1.hashCode, req2.hashCode);
    });

    test('different weekday values → not equal', () {
      final req1 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_a': {1, 4, 7}},
      );
      final req2 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_a': {2, 5, 7}},
      );
      expect(req1, isNot(req2));
    });

    test('different material keys → not equal', () {
      final r1 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_a': {1}},
      );
      final r2 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {'mat_b': {1}},
      );
      expect(r1, isNot(r2));
    });

    test('null and empty map are not equal', () {
      final reqNull = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: null,
      );
      final reqEmpty = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {},
      );
      expect(reqNull, isNot(reqEmpty));
    });

    test('empty maps are equal', () {
      final req1 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {},
      );
      final req2 = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: {},
      );
      expect(req1, req2);
      expect(req1.hashCode, req2.hashCode);
    });

    test('hashCode access does not mutate source', () {
      final source = <String, Set<int>>{'mat_a': {1, 4}};
      final before = source.length;
      final req = GrowthRouteRequest(
        goalIds: ['goal-a'], startDate: _testDate, startWeekday: 1,
        weekdayMap: source,
      );
      final h = req.hashCode;
      expect(h, isNotNull);
      expect(source.length, before);
      expect(source['mat_a'], {1, 4});
    });
  });
}
