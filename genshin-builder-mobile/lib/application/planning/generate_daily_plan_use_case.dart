import '../../domain/account/account_snapshot.dart';
import '../../domain/daily_materials/daily_material_models.dart';
import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/planning/upgrade_option.dart';
import '../../domain/recommendation/recommendation.dart';

/// Generates a bounded, deterministic daily-plan candidate list.
///
/// DeepSeek never creates candidates: it can only rank these existing IDs.
class GenerateDailyPlanUseCase {
  const GenerateDailyPlanUseCase();

  DailyPlan call({
    required String userId,
    required AccountSnapshot snapshot,
    required DateTime date,
    required int weekday,
    DailyMaterialsPlan? materialsPlan,
    List<UpgradeOption> upgradeOptions = const [],
    Set<String> weekdayLimitedMaterialIds = const {},
    Set<String> availableMaterialIdsToday = const {},
    Set<String> bookmarkedCharacterIds = const {},
    int? weekdayRunResinCost,
    int? weeklyBossRunResinCost,
    DateTime? generatedAt,
  }) {
    final items = <DailyPlanItem>[];
    final goals = [...snapshot.activeGoals]..sort(
      (a, b) =>
          b.priority.compareTo(a.priority) != 0
              ? b.priority.compareTo(a.priority)
              : a.id.compareTo(b.id),
    );
    final inventory = snapshot.materialInventory;
    final hasInventory = inventory.isNotEmpty;
    final resin = snapshot.currentResin;
    final missingData = <MissingData>[];

    if (!hasInventory) missingData.add(MissingData.materialInventory);
    if (resin == null) missingData.add(MissingData.currentResin);

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
          estimatedResinCost: weekdayRunResinCost,
          estimatedMinutes: 20,
          hasInventory: hasInventory,
          missingData: missingData,
        ),
      );
      items.addAll(
        _weekdayItems(
          cards: materialsPlan.weeklyBossCards,
          type: DailyPlanItemType.weeklyBoss,
          idPrefix: 'wb',
          basePriority: 85,
          reason: '週ボス素材の不足',
          estimatedResinCost: weeklyBossRunResinCost,
          estimatedMinutes: 30,
          hasInventory: hasInventory,
          missingData: missingData,
        ),
      );
    }

    final goalIdsWithOptions = <String>{};
    final sortedOptions = [...upgradeOptions]..sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      final byGap = _optionGap(b).compareTo(_optionGap(a));
      if (byGap != 0) return byGap;
      return a.optionId.compareTo(b.optionId);
    });
    final characterNames = {
      for (final character in snapshot.characters)
        character.characterId: character.name,
    };

    for (final option in sortedOptions) {
      if (option.relatedGoalId != null) {
        goalIdsWithOptions.add(option.relatedGoalId!);
      }
      final materialIds = _neededMaterialIds(option);
      final limitedIds =
          materialIds.where(weekdayLimitedMaterialIds.contains).toSet();
      final availableToday =
          limitedIds.isEmpty ||
          limitedIds.every(availableMaterialIdsToday.contains);
      final gap = _optionGap(option);
      final bookmarked = bookmarkedCharacterIds.contains(option.characterId);
      final reasons = <String>[
        if (gap > 0) '目標との差 $gap',
        if (option.priority > 0) '既存の目標優先度 ${option.priority}',
        if (limitedIds.isNotEmpty && availableToday) '対象の曜日素材を本日入手可能',
        if (limitedIds.isNotEmpty && !availableToday) '対象の曜日素材は本日入手不可',
        if (bookmarked) 'ブックマーク中の育成対象',
      ];
      items.add(
        DailyPlanItem(
          id: option.optionId,
          type: _itemType(option.optionType),
          title: _optionTitle(
            option,
            characterNames[option.characterId] ?? option.characterId,
          ),
          characterIds: [option.characterId],
          materialIds: materialIds.take(16).toList(),
          priority: 70 + option.priority + gap.clamp(0, 30),
          relatedGoalId: option.relatedGoalId,
          reasons: reasons.isEmpty ? const ['育成目標の未完了項目'] : reasons,
          estimatedResinCost: option.estimatedResinCost,
          estimatedMinutes: _estimatedMinutes(option.optionType),
          currentLevel: option.fromValue,
          targetLevel: option.toValue,
          availableToday: availableToday,
          requiresResin: (option.estimatedResinCost ?? 0) > 0,
          bookmarked: bookmarked,
          confidence: option.confidence,
          missingData: option.missingData,
        ),
      );
    }

    // Keep the existing goal fallback when master data cannot produce an option.
    for (final goal in goals.where((g) => !goalIdsWithOptions.contains(g.id))) {
      final bookmarked = bookmarkedCharacterIds.contains(goal.characterId);
      items.add(
        DailyPlanItem(
          id: goal.priority > 0 ? 'pri_${goal.id}' : 'gen_${goal.id}',
          type:
              goal.priority > 0
                  ? DailyPlanItemType.growthGoal
                  : DailyPlanItemType.generalMaterial,
          title:
              goal.priority > 0
                  ? '優先: ${_goalSummary(goal)}'
                  : _goalSummary(goal),
          characterIds: [goal.characterId],
          priority: (goal.priority > 0 ? 80 : 50) + goal.priority,
          relatedGoalId: goal.id,
          reasons: [
            goal.priority > 0 ? '優先度の高い育成目標' : '育成目標の未完了項目',
            if (bookmarked) 'ブックマーク中の育成対象',
          ],
          bookmarked: bookmarked,
          confidence:
              hasInventory
                  ? RecommendationConfidence.high
                  : RecommendationConfidence.low,
          missingData: missingData,
        ),
      );
    }

    items.sort((a, b) {
      final byAvailability = (b.availableToday ? 1 : 0).compareTo(
        a.availableToday ? 1 : 0,
      );
      if (byAvailability != 0) return byAvailability;
      final byBookmark = (b.bookmarked ? 1 : 0).compareTo(a.bookmarked ? 1 : 0);
      if (byBookmark != 0) return byBookmark;
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return a.id.compareTo(b.id);
    });

    return DailyPlan(
      userId: userId,
      date: date,
      items: items.take(20).toList(),
      currentResin: resin,
      maxResin: snapshot.maxResin,
      confidence:
          hasInventory
              ? RecommendationConfidence.high
              : RecommendationConfidence.low,
      completeness: snapshot.completeness,
      missingData: missingData,
      generatedAt: generatedAt ?? DateTime.now(),
      ruleVersion: '3',
    );
  }

  List<DailyPlanItem> _weekdayItems({
    required List<DailyMaterialSeriesCardData> cards,
    required DailyPlanItemType type,
    required String idPrefix,
    required int basePriority,
    required String reason,
    required int? estimatedResinCost,
    required int estimatedMinutes,
    required bool hasInventory,
    required List<MissingData> missingData,
  }) {
    final ranked =
        cards.where((c) => c.totalRemaining > 0).toList()
          ..sort((a, b) => b.totalRemaining.compareTo(a.totalRemaining));
    final out = <DailyPlanItem>[];
    for (final card in ranked.take(4)) {
      final materialIds =
          card.remainingByMaterialId.entries
              .where((entry) => entry.value > 0)
              .map((entry) => entry.key)
              .take(16)
              .toList();
      final characterIds = _characterIdsForCard(card);
      final bookmarked = card.consumers.any((consumer) => consumer.isBuilding);
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
          reasons: [
            reason,
            '不足 ${card.totalRemaining}',
            if (bookmarked) 'ブックマーク中の育成対象',
          ],
          estimatedResinCost: estimatedResinCost,
          estimatedMinutes: estimatedMinutes,
          availableToday: true,
          requiresResin: true,
          bookmarked: bookmarked,
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
        ids.addAll(consumer.equippedCharacters.map((entry) => entry.id));
      } else if (consumer.weaponType == null) {
        ids.add(consumer.id);
      }
    }
    return ids.take(8).toList();
  }

  List<String> _neededMaterialIds(UpgradeOption option) {
    final remaining =
        option.remainingMaterials.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key)
            .toList();
    if (remaining.isNotEmpty) return remaining;
    return {...option.materialsCost.keys, ...option.expItemCost.keys}.toList();
  }

  int _optionGap(UpgradeOption option) {
    final from = option.fromValue;
    final to = option.toValue;
    if (from == null || to == null || to <= from) return 0;
    return to - from;
  }

  DailyPlanItemType _itemType(String optionType) {
    return switch (optionType) {
      'level' => DailyPlanItemType.characterLevel,
      'ascension' => DailyPlanItemType.characterAscension,
      'talentNormal' ||
      'talentSkill' ||
      'talentBurst' => DailyPlanItemType.talent,
      'weapon' => DailyPlanItemType.weapon,
      _ => DailyPlanItemType.growthGoal,
    };
  }

  String _optionTitle(UpgradeOption option, String characterName) {
    final target = option.toValue;
    return switch (option.optionType) {
      'level' => '$characterNameをLv.$targetへ',
      'ascension' => '$characterNameを突破$target段階へ',
      'talentNormal' => '$characterNameの通常攻撃をLv.$targetへ',
      'talentSkill' => '$characterNameの元素スキルをLv.$targetへ',
      'talentBurst' => '$characterNameの元素爆発をLv.$targetへ',
      'weapon' => '$characterNameの武器をLv.$targetへ',
      _ => '$characterNameの育成目標',
    };
  }

  int _estimatedMinutes(String optionType) {
    return switch (optionType) {
      'talentNormal' || 'talentSkill' || 'talentBurst' || 'weapon' => 20,
      'ascension' => 25,
      _ => 20,
    };
  }

  String _goalSummary(GrowthGoal goal) {
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
    return parts.isEmpty ? goal.characterId : parts.join(' + ');
  }
}
