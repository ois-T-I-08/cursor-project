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

    if (!hasInventory) missingData.add(MissingData.materialInventory);
    if (resin == null) missingData.add(MissingData.currentResin);

    // 1. High-priority goals. Weekday-specific tasks are produced by the
    // dedicated daily-material planner, not guessed here.
    for (final goal in goals.where((g) => g.priority > 0).take(2)) {
      items.add(DailyPlanItem(
        id: 'pri_${goal.id}',
        type: DailyPlanItemType.growthGoal,
        title: '優先: ${_goalSummary(goal)}',
        characterIds: [goal.characterId],
        priority: 80 + goal.priority,
        relatedGoalId: goal.id,
        reasons: ['優先度の高い育成目標'],
        estimatedResinCost: resin,
        confidence: hasInventory ? RecommendationConfidence.high : RecommendationConfidence.low,
        missingData: missingData,
      ));
    }

    // 2. General goals
    for (final goal in goals.where((g) => g.priority <= 0).take(2)) {
      items.add(DailyPlanItem(
        id: 'gen_${goal.id}',
        type: DailyPlanItemType.generalMaterial,
        title: _goalSummary(goal),
        characterIds: [goal.characterId],
        priority: 50,
        relatedGoalId: goal.id,
        reasons: ['育成素材集め'],
        confidence: hasInventory ? RecommendationConfidence.high : RecommendationConfidence.low,
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
      confidence: hasInventory ? RecommendationConfidence.high : RecommendationConfidence.low,
      completeness: snapshot.completeness,
      missingData: missingData,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }

  String _goalSummary(GrowthGoal goal) {
    final parts = <String>[];
    if (goal.targetLevel != null) parts.add('Lv.${goal.targetLevel}');
    if (goal.targetTalentNormal != null ||
        goal.targetTalentSkill != null ||
        goal.targetTalentBurst != null) {
      parts.add('天賦');
    }
    if (goal.targetWeaponId != null) parts.add('武器');
    return parts.isEmpty ? goal.characterId : parts.join(' + ');
  }
}
