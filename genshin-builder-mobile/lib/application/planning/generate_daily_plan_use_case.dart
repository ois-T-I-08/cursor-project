import '../../domain/account/account_snapshot.dart';
import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/recommendation/recommendation.dart';

/// Generates a daily plan from an [AccountSnapshot].
///
/// Priority rules:
/// 1. Weekday-limited materials
/// 2. Weekly boss materials
/// 3. High-priority GrowthGoals
/// 4. Near-completion goals
/// 5. Items achievable with current resin
/// 6. General materials
class GenerateDailyPlanUseCase {
  const GenerateDailyPlanUseCase();

  /// Generate a daily plan for a specific date and weekday.
  DailyPlan call({
    required String userId,
    required AccountSnapshot snapshot,
    required DateTime date,
    required int weekday, // 1=Mon..7=Sun
    DateTime? generatedAt,
  }) {
    final items = <DailyPlanItem>[];
    final goals = snapshot.activeGoals;
    final inventory = snapshot.materialInventory;
    final hasInventory = inventory.isNotEmpty;
    final resin = snapshot.currentResin;
    final missingData = <MissingData>[];
    final names = {
      for (final c in snapshot.characters) c.characterId: c.name,
    };

    if (!hasInventory) missingData.add(MissingData.materialInventory);
    if (resin == null) missingData.add(MissingData.currentResin);

    // アクティブな育成目標をすべて今日やることへ反映（件数上限で落とさない）
    for (final goal in goals) {
      final high = goal.priority > 0;
      items.add(DailyPlanItem(
        id: '${high ? 'pri' : 'gen'}_${goal.id}',
        type: high
            ? DailyPlanItemType.growthGoal
            : DailyPlanItemType.generalMaterial,
        title: high
            ? '優先: ${_goalSummary(goal, names)}'
            : _goalSummary(goal, names),
        characterIds: [goal.characterId],
        priority: high ? 80 + goal.priority : 50,
        relatedGoalId: goal.id,
        reasons: [
          high ? '優先度の高い育成目標' : '育成素材集め',
        ],
        estimatedResinCost: null,
        confidence: hasInventory
            ? RecommendationConfidence.high
            : RecommendationConfidence.low,
        missingData: missingData,
      ));
    }

    items.sort((a, b) => b.priority.compareTo(a.priority));

    return DailyPlan(
      userId: userId,
      date: date,
      items: items,
      currentResin: resin,
      maxResin: snapshot.maxResin,
      confidence: hasInventory
          ? RecommendationConfidence.high
          : RecommendationConfidence.low,
      completeness: snapshot.completeness,
      missingData: missingData,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }

  String _goalSummary(GrowthGoal goal, Map<String, String> names) {
    final charName = _resolveCharacterName(goal.characterId, names);
    final parts = <String>[];
    if (goal.targetLevel != null) parts.add('Lv.${goal.targetLevel}');
    if (goal.targetTalentNormal != null ||
        goal.targetTalentSkill != null ||
        goal.targetTalentBurst != null) {
      parts.add('天賦');
    }
    if (goal.targetWeaponId != null || goal.targetWeaponLevel != null) {
      parts.add('武器');
    }
    final focus = parts.isEmpty ? '育成' : parts.join('・');
    if (charName != null) {
      return '$charName（$focus）';
    }
    return focus;
  }

  /// HoYoLAB ID（接尾辞付き）とマスタ ID のゆれを吸収して表示名を解決する。
  String? _resolveCharacterName(
    String characterId,
    Map<String, String> names,
  ) {
    final direct = names[characterId];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final base = characterId.split('-').first;
    final byBase = names[base];
    if (byBase != null && byBase.trim().isNotEmpty) return byBase.trim();

    for (final e in names.entries) {
      if (e.key == base || e.key.startsWith('$base-')) {
        final n = e.value.trim();
        if (n.isNotEmpty) return n;
      }
    }
    return null;
  }
}
