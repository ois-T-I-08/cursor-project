import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/domain/history/growth_event.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_goal.dart';
import 'package:genshin_builder_mobile/domain/recommendation/recommendation.dart';

void main() {
  group('GrowthGoal', () {
    test('validate rejects empty id', () {
      const g = GrowthGoal(id: '', userId: 'u1', characterId: 'c1', targetLevel: 90);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate rejects empty userId', () {
      const g = GrowthGoal(id: 'g1', userId: '', characterId: 'c1', targetLevel: 90);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate rejects empty characterId', () {
      const g = GrowthGoal(id: 'g1', userId: 'u1', characterId: '', targetLevel: 90);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate rejects no targets', () {
      const g = GrowthGoal(id: 'g1', userId: 'u1', characterId: 'c1');
      expect(g.hasAnyTarget, isFalse);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate rejects invalid level', () {
      const g = GrowthGoal(id: 'g1', userId: 'u1', characterId: 'c1', targetLevel: 91);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate rejects invalid ascension', () {
      const g = GrowthGoal(id: 'g1', userId: 'u1', characterId: 'c1', targetAscension: 7);
      expect(GrowthGoal.validate(g), isNotNull);
    });

    test('validate accepts valid goal', () {
      const g = GrowthGoal(
        id: 'g1',
        userId: 'u1',
        characterId: 'c1',
        targetLevel: 90,
        targetTalentNormal: 10,
      );
      expect(GrowthGoal.validate(g), isNull);
    });

    test('partial goal (talent only) is valid', () {
      const g = GrowthGoal(
        id: 'g1',
        userId: 'u1',
        characterId: 'c1',
        targetTalentSkill: 8,
      );
      expect(g.hasAnyTarget, isTrue);
      expect(GrowthGoal.validate(g), isNull);
    });

    test('hasAnyTarget false when all null', () {
      const g = GrowthGoal(id: 'g1', userId: 'u1', characterId: 'c1');
      expect(g.hasAnyTarget, isFalse);
    });

    test('hasAnyTarget true when weapon set', () {
      const g = GrowthGoal(
        id: 'g1',
        userId: 'u1',
        characterId: 'c1',
        targetWeaponId: 'w1',
      );
      expect(g.hasAnyTarget, isTrue);
    });
  });

  group('GrowthEvent', () {
    test('makeDedupKey is stable', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1000000);
      final k1 = GrowthEvent.makeDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        observedAt: dt,
      );
      final k2 = GrowthEvent.makeDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        observedAt: dt,
      );
      expect(k1, k2);
    });

    test('makeValueDedupKey is stable', () {
      final k1 = GrowthEvent.makeValueDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        before: '80',
        after: '90',
      );
      final k2 = GrowthEvent.makeValueDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        before: '80',
        after: '90',
      );
      expect(k1, k2);
    });

    test('different before/after makes different dedupKey', () {
      final k1 = GrowthEvent.makeValueDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        before: '80',
        after: '90',
      );
      final k2 = GrowthEvent.makeValueDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        before: '70',
        after: '90',
      );
      expect(k1, isNot(k2));
    });

    test('different users do not collide', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1000000);
      final k1 = GrowthEvent.makeDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        observedAt: dt,
      );
      final k2 = GrowthEvent.makeDedupKey(
        userId: 'u2',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        observedAt: dt,
      );
      expect(k1, isNot(k2));
    });

    test('different event types do not collide', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1000000);
      final k1 = GrowthEvent.makeDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.characterLevelChanged,
        observedAt: dt,
      );
      final k2 = GrowthEvent.makeDedupKey(
        userId: 'u1',
        characterId: 'c1',
        eventType: GrowthEventType.talentNormalChanged,
        observedAt: dt,
      );
      expect(k1, isNot(k2));
    });
  });

  group('Recommendation', () {
    test('recommendation holds reasons', () {
      const reason = RecommendationReason(message: 'Very strong synergy');
      const rec = Recommendation(
        recommendationId: 'r1',
        recommendationType: 'growth',
        targetType: 'character',
        targetId: 'c1',
        reasons: [reason],
      );
      expect(rec.reasons.length, 1);
      expect(rec.reasons.first.message, 'Very strong synergy');
    });

    test('missingData is independent of confidence', () {
      const rec = Recommendation(
        recommendationId: 'r1',
        recommendationType: 'test',
        targetType: 'c',
        targetId: 'x',
        confidence: RecommendationConfidence.high,
        completeness: DataCompleteness.partial,
        missingData: [MissingData.materialInventory],
      );
      expect(rec.confidence, RecommendationConfidence.high);
      expect(rec.completeness, DataCompleteness.partial);
      expect(rec.missingData, [MissingData.materialInventory]);
    });
  });

  group('RecommendationReason', () {
    test('default importance is 1', () {
      const r = RecommendationReason(message: 'Test');
      expect(r.importance, 1);
    });
  });
}
