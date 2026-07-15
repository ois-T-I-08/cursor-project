import '../../domain/account/account_snapshot.dart';
import '../../domain/models/calculation_models.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/planning/upgrade_option.dart';
import '../../domain/recommendation/recommendation.dart';
import '../../domain/level_config.dart';
import '../../domain/material_requirements.dart';

/// Generates UpgradeOptions from GrowthGoals + AccountSnapshot.
class GenerateUpgradeOptionsUseCase {
  const GenerateUpgradeOptionsUseCase();

  List<UpgradeOption> call({
    required GrowthGoal goal,
    required CharacterSnapshot character,
    required Map<String, int> materialInventory,
    List<PromoteStage>? promotes,
    Map<String, List<TalentLevelUpgrade>>? talents,
    List<PromoteStage>? weaponPromotes,
    List<String>? weaponLevelUpItemIds,
    int weaponRarity = 5,
    required DateTime generatedAt,
  }) {
    final options = <UpgradeOption>[];
    final hasInv = materialInventory.isNotEmpty;
    final sources = <String>['masterData', 'userProgress'];
    if (hasInv) sources.add('materialInventory');
    final now = generatedAt;

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
          expMaterialIds:
              expBooks.map((item) => item.id).toSet(),
          materialInventory: materialInventory,
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
          promotes: promotes,
          materialInventory: materialInventory,
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
            talentUpgrades: talents?[tc.$1],
            materialInventory: materialInventory,
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
          weaponPromotes: weaponPromotes,
          expMaterialIds: weaponLevelUpItemIds?.toSet(),
          weaponRarity: weaponRarity,
          materialInventory: materialInventory,
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
    List<TalentLevelUpgrade>? talentUpgrades,
    List<PromoteStage>? weaponPromotes,
    Set<String>? expMaterialIds,
    int weaponRarity = 5,
    required Map<String, int> materialInventory,
  }) {
    final materials = <String, int>{};
    var mora = 0;
    final expItems = <String, int>{};
    CalculationMode calcMode = CalculationMode.exactMasterData;
    var invStatus = InventoryStatus.notSet;
    final missing = <MissingData>[];

    if (type == 'level' && promotes != null && promotes.isNotEmpty) {
      _mergeLines(
        getRangeLevelRequirements(fromVal, toVal, promotes, 'character'),
        materials,
        expItems,
        expMaterialIds,
        (value) => mora += value,
      );
    } else if (type == 'ascension' &&
        promotes != null &&
        promotes.isNotEmpty) {
      for (final stage in promotes) {
        if (stage.promoteLevel <= fromVal || stage.promoteLevel > toVal) {
          continue;
        }
        for (final entry in stage.costItems.entries) {
          materials[entry.key] =
              (materials[entry.key] ?? 0) + entry.value;
        }
        mora += stage.coinCost;
      }
    } else if (type.startsWith('talent') &&
        talentUpgrades != null &&
        talentUpgrades.isNotEmpty) {
      _mergeLines(
        getRangeTalentRequirements(
          fromVal,
          toVal,
          talentLevelMax,
          talentUpgrades,
        ),
        materials,
        expItems,
        null,
        (value) => mora += value,
      );
    } else if (type == 'weapon' &&
        weaponPromotes != null &&
        weaponPromotes.isNotEmpty) {
      _mergeLines(
        getRangeLevelRequirements(
          fromVal,
          toVal,
          weaponPromotes,
          'weapon',
          weaponRarity: weaponRarity,
        ),
        materials,
        expItems,
        expMaterialIds,
        (value) => mora += value,
      );
    } else {
      calcMode = CalculationMode.unavailable;
      missing.add(MissingData.masterUpgradeData);
    }

    if (!hasInv) {
      missing.add(MissingData.materialInventory);
      if (calcMode != CalculationMode.unavailable) {
        calcMode = CalculationMode.estimatedInventoryMissing;
      }
    } else {
      invStatus = InventoryStatus.ownedInsufficient;
    }

    final remaining = <String, int>{};
    final owned = <String, int>{};
    if (hasInv) {
      for (final entry in [
        ...materials.entries,
        ...expItems.entries,
      ]) {
        final quantity = materialInventory[entry.key] ?? 0;
        owned[entry.key] = quantity;
        remaining[entry.key] =
            (entry.value - quantity).clamp(0, entry.value).toInt();
      }
      invStatus = remaining.values.any((value) => value > 0)
          ? InventoryStatus.ownedInsufficient
          : InventoryStatus.ownedSufficient;
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
      ownedMaterials: owned,
      remainingMaterials: remaining,
      inventoryStatus: invStatus,
      priority: goal.priority,
      confidence:
          calcMode == CalculationMode.unavailable
              ? RecommendationConfidence.unknown
              : hasInv
                  ? RecommendationConfidence.high
                  : RecommendationConfidence.low,
      completeness:
          calcMode == CalculationMode.unavailable
              ? DataCompleteness.unavailable
              : hasInv
                  ? DataCompleteness.partial
                  : DataCompleteness.minimal,
      missingData: missing,
      usedDataSources: sources,
      calculationMode: calcMode,
      generatedAt: now,
    );
  }

  void _mergeLines(
    List<RequirementLine> lines,
    Map<String, int> materials,
    Map<String, int> expItems,
    Set<String>? expMaterialIds,
    void Function(int mora) addMora,
  ) {
    for (final line in lines) {
      if (line.isMora) {
        addMora(line.count);
      } else if (expMaterialIds?.contains(line.materialId) ?? false) {
        expItems[line.materialId] =
            (expItems[line.materialId] ?? 0) + line.count;
      } else {
        materials[line.materialId] =
            (materials[line.materialId] ?? 0) + line.count;
      }
    }
  }
}
