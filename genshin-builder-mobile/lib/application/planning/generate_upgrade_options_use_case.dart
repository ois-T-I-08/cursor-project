import '../../domain/account/account_snapshot.dart';
import '../../domain/models/calculation_models.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/planning/upgrade_option.dart';
import '../../domain/recommendation/recommendation.dart';
import '../../domain/level_progression.dart';

/// Generates UpgradeOptions from GrowthGoals + AccountSnapshot.
class GenerateUpgradeOptionsUseCase {
  const GenerateUpgradeOptionsUseCase();

  List<UpgradeOption> call({
    required GrowthGoal goal,
    required CharacterSnapshot character,
    required Map<String, int> materialInventory,
    List<PromoteStage>? promotes,
    DateTime? generatedAt,
  }) {
    final options = <UpgradeOption>[];
    final hasInv = materialInventory.isNotEmpty;
    final sources = <String>['masterData', 'userProgress'];
    if (hasInv) sources.add('materialInventory');
    final now = generatedAt ?? DateTime.now();

    // Level
    if (goal.targetLevel != null && goal.targetLevel! > character.level) {
      options.add(
        _makeOption(
          goal: goal,
          character: character,
          type: 'level',
          fromVal: character.level,
          toVal: goal.targetLevel!,
          hasInv: hasInv,
          sources: sources,
          now: now,
          promotes: promotes,
        ),
      );
    }
    // Ascension
    if (goal.targetAscension != null &&
        goal.targetAscension! > character.ascension) {
      options.add(
        _makeOption(
          goal: goal,
          character: character,
          type: 'ascension',
          fromVal: character.ascension,
          toVal: goal.targetAscension!,
          hasInv: hasInv,
          sources: sources,
          now: now,
        ),
      );
    }
    // Talents
    for (final tc in [
      ('talentNormal', character.talentNormal, goal.targetTalentNormal),
      ('talentSkill', character.talentSkill, goal.targetTalentSkill),
      ('talentBurst', character.talentBurst, goal.targetTalentBurst),
    ]) {
      if (tc.$3 != null && tc.$3! > tc.$2) {
        options.add(
          _makeOption(
            goal: goal,
            character: character,
            type: tc.$1,
            fromVal: tc.$2,
            toVal: tc.$3!,
            hasInv: hasInv,
            sources: sources,
            now: now,
          ),
        );
      }
    }
    // Weapon
    if (goal.targetWeaponLevel != null &&
        goal.targetWeaponLevel! > character.weaponLevel) {
      options.add(
        _makeOption(
          goal: goal,
          character: character,
          type: 'weapon',
          fromVal: character.weaponLevel,
          toVal: goal.targetWeaponLevel!,
          hasInv: hasInv,
          sources: sources,
          now: now,
        ),
      );
    }
    return options;
  }

  UpgradeOption _makeOption({
    required GrowthGoal goal,
    required CharacterSnapshot character,
    required String type,
    required int fromVal,
    required int toVal,
    required bool hasInv,
    required List<String> sources,
    required DateTime now,
    List<PromoteStage>? promotes,
  }) {
    final materials = <String, int>{};
    var mora = 0;
    final expItems = <String, int>{};
    CalculationMode calcMode = CalculationMode.exactMasterData;
    var invStatus = InventoryStatus.notSet;
    final missing = <MissingData>[];

    if (type == 'level' && promotes != null && promotes.isNotEmpty) {
      final next = getNextStageRequirements(fromVal, promotes, 'character', 0);
      if (next != null) {
        for (final mc in next.materials) {
          materials[mc.materialId] = (materials[mc.materialId] ?? 0) + mc.count;
        }
        mora += next.mora;
        for (final lu in next.levelUpMaterials) {
          expItems[lu.materialId] = (expItems[lu.materialId] ?? 0) + lu.count;
        }
      }
    }

    if (!hasInv) {
      missing.add(MissingData.materialInventory);
      calcMode = CalculationMode.estimatedInventoryMissing;
    } else {
      invStatus = InventoryStatus.ownedInsufficient;
    }

    final remaining = <String, int>{};
    if (hasInv) {
      for (final entry in materials.entries) {
        remaining[entry.key] = entry.value; // no inventory per-material yet
      }
    }

    return UpgradeOption(
      optionId: '${goal.id}_$type',
      characterId: character.characterId,
      optionType: type,
      relatedGoalId: goal.id,
      fromValue: fromVal,
      toValue: toVal,
      stepCount: toVal - fromVal,
      materialsCost: materials,
      moraCost: mora,
      expItemCost: expItems,
      remainingMaterials: remaining,
      inventoryStatus: invStatus,
      priority: goal.priority,
      confidence:
          hasInv ? RecommendationConfidence.high : RecommendationConfidence.low,
      completeness:
          hasInv ? DataCompleteness.partial : DataCompleteness.minimal,
      missingData: missing,
      usedDataSources: sources,
      calculationMode: calcMode,
      generatedAt: now,
    );
  }
}
