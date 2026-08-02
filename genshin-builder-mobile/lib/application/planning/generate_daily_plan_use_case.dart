import '../../domain/account/account_snapshot.dart';
import '../../domain/daily_materials/daily_material_models.dart';
import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/recommendation/recommendation.dart';

/// Generates a daily plan from an [AccountSnapshot] and optional weekday materials.
///
/// Priority rules:
/// 1. Weekday-limited materials (from DailyMaterialsPlan)
/// 2. Weekly boss materials
/// 3. High-priority GrowthGoals
/// 4. General goals
class GenerateDailyPlanUseCase {
  const GenerateDailyPlanUseCase();

  /// Generate a daily plan for a specific date and weekday.
  DailyPlan call({
    required String userId,
    required AccountSnapshot snapshot,
    required DateTime date,
    required int weekday, // 1=Mon..7=Sun
    DailyMaterialsPlan? materialsPlan,
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

    // 1. Weekday talent/weapon series with remaining needs.
    if (materialsPlan != null) {
      items.addAll(
        _weekdayItems(
          cards: [
            ...materialsPlan.talentCards,
            ...materialsPlan.weaponCards,
            ...materialsPlan.artifactCards,
          ],
          type: DailyPlanItemType.weekdayMaterial,
          idPrefix: 'wd',
          basePriority: 90,
          reason: '今日開放の曜日素材',
          hasInventory: hasInventory,
          missingData: missingData,
        ),
      );

      // 2. Weekly boss cards.
      items.addAll(
        _weekdayItems(
          cards: materialsPlan.weeklyBossCards,
          type: DailyPlanItemType.weeklyBoss,
          idPrefix: 'wb',
          basePriority: 85,
          reason: '週ボス素材の不足',
          hasInventory: hasInventory,
          missingData: missingData,
        ),
      );
    }

    // 3. High-priority goals.
    for (final goal in goals.where((g) => g.priority > 0).take(2)) {
      items.add(
        DailyPlanItem(
          id: 'pri_${goal.id}',
          type: DailyPlanItemType.growthGoal,
          title: '優先: ${_goalSummary(goal)}',
          characterIds: [goal.characterId],
          priority: 80 + goal.priority,
          relatedGoalId: goal.id,
          reasons: ['優先度の高い育成目標'],
          estimatedResinCost: null,
          confidence:
              hasInventory
                  ? RecommendationConfidence.high
                  : RecommendationConfidence.low,
          missingData: missingData,
        ),
      );
    }

    // 4. General goals
    for (final goal in goals.where((g) => g.priority <= 0).take(2)) {
      items.add(
        DailyPlanItem(
          id: 'gen_${goal.id}',
          type: DailyPlanItemType.generalMaterial,
          title: _goalSummary(goal),
          characterIds: [goal.characterId],
          priority: 50,
          relatedGoalId: goal.id,
          reasons: ['育成素材集め'],
          confidence:
              hasInventory
                  ? RecommendationConfidence.high
                  : RecommendationConfidence.low,
          missingData: missingData,
        ),
      );
    }

    items.sort((a, b) => b.priority.compareTo(a.priority));

    return DailyPlan(
      userId: userId,
      date: date,
      items: items.take(8).toList(),
      currentResin: resin,
      maxResin: snapshot.maxResin,
      confidence:
          hasInventory
              ? RecommendationConfidence.high
              : RecommendationConfidence.low,
      completeness: snapshot.completeness,
      missingData: missingData,
      generatedAt: generatedAt ?? DateTime.now(),
      ruleVersion: '2',
    );
  }

  List<DailyPlanItem> _weekdayItems({
    required List<DailyMaterialSeriesCardData> cards,
    required DailyPlanItemType type,
    required String idPrefix,
    required int basePriority,
    required String reason,
    required bool hasInventory,
    required List<MissingData> missingData,
  }) {
    final ranked =
        cards.where((c) => c.totalRemaining > 0).toList()
          ..sort((a, b) => b.totalRemaining.compareTo(a.totalRemaining));
    final out = <DailyPlanItem>[];
    for (final card in ranked.take(3)) {
      final materialIds = card.remainingByMaterialId.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .take(6)
          .toList();
      final characterIds = _characterIdsForCard(card);
      final label = card.series.name;
      final displayName = card.displayMaterial?.name;
      out.add(
        DailyPlanItem(
          id: '${idPrefix}_${card.series.id}',
          type: type,
          title:
              displayName == null || displayName.isEmpty
                  ? label
                  : '$label（$displayName など）',
          description: '不足合計 ${card.totalRemaining}',
          characterIds: characterIds,
          materialIds: materialIds,
          priority: basePriority + (card.totalRemaining > 20 ? 5 : 0),
          reasons: [reason, '不足 ${card.totalRemaining}'],
          estimatedResinCost: null,
          confidence:
              hasInventory
                  ? RecommendationConfidence.high
                  : RecommendationConfidence.medium,
          missingData: missingData,
        ),
      );
    }
    return out;
  }

  List<String> _characterIdsForCard(DailyMaterialSeriesCardData card) {
    final ids = <String>{};
    for (final consumer in card.consumers) {
      if (consumer.equippedCharacters.isNotEmpty) {
        ids.addAll(consumer.equippedCharacters.map((e) => e.id));
      } else if (consumer.weaponType == null) {
        ids.add(consumer.id);
      }
    }
    return ids.take(6).toList();
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
