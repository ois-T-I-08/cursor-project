/// Extended upgrade option with cost calculation details.
///
/// Values come from Amber master data (golden-protected calculations)
/// and user progress/material inventory.
library;

import '../recommendation/recommendation.dart';

enum CalculationMode {
  exactMasterData,
  exactProgressDifference,
  estimatedInventoryMissing,
  relativeImpactOnly,
  unavailable,
}

enum InventoryStatus { ownedSufficient, ownedInsufficient, notSet, unknown }

class UpgradeOption {
  const UpgradeOption({
    required this.optionId,
    required this.characterId,
    required this.optionType,
    this.relatedGoalId,
    this.fromValue,
    this.toValue,
    this.stepCount = 1,
    this.materialsCost = const {},
    this.moraCost = 0,
    this.expItemCost = const {},
    this.estimatedResinCost,
    this.ownedMaterials = const {},
    this.remainingMaterials = const {},
    this.inventoryStatus = InventoryStatus.unknown,
    this.impact,
    this.priority = 0,
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.usedDataSources = const [],
    this.calculationMode = CalculationMode.unavailable,
    this.generatedAt,
    this.ruleVersion = '1',
  });

  final String optionId;
  final String characterId;
  final String
  optionType; // level, ascension, talentNormal, talentSkill, talentBurst, weapon
  final String? relatedGoalId;
  final int? fromValue;
  final int? toValue;
  final int stepCount;
  final Map<String, int> materialsCost;
  final int moraCost;
  final Map<String, int> expItemCost;
  final int? estimatedResinCost;
  final Map<String, int> ownedMaterials;
  final Map<String, int> remainingMaterials;
  final InventoryStatus inventoryStatus;
  final UpgradeImpact? impact;
  final int priority;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final List<String> usedDataSources;
  final CalculationMode calculationMode;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get isCalculable => calculationMode != CalculationMode.unavailable;
}

enum ImpactBand { veryHigh, high, medium, low, minimal, unknown }

class UpgradeImpact {
  const UpgradeImpact({
    this.impactScore = 0,
    this.impactBand = ImpactBand.unknown,
    this.affectedAreas = const [],
    this.reasons = const [],
    this.confidence = RecommendationConfidence.unknown,
    this.calculationMode = CalculationMode.unavailable,
    this.excludedFactors = const [],
    this.notes,
    this.ruleVersion = '1',
  });

  final double impactScore;
  final ImpactBand impactBand;
  final List<String> affectedAreas;
  final List<String> reasons;
  final RecommendationConfidence confidence;
  final CalculationMode calculationMode;
  final List<String> excludedFactors;
  final String? notes;
  final String ruleVersion;

  double? get efficiencyScore {
    // Not implemented — requires resin cost data
    return null;
  }
}
