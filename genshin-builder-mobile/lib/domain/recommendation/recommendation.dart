/// Recommendation models for growth planning and team building.
///
/// These are domain models — no external API DTOs or DB rows.
library;

enum RecommendationConfidence {
  high,
  medium,
  low,
  unknown,
}

enum DataCompleteness {
  complete,
  partial,
  minimal,
  unavailable,
}

enum MissingData {
  masterUpgradeData,
  materialInventory,
  currentResin,
  unequippedWeapons,
  currentAbyssEnemies,
  currentTheaterRules,
  teamUsageStatistics,
}

class RecommendationReason {
  const RecommendationReason({
    required this.message,
    this.reasonCode,
    this.importance = 1,
    this.relatedCharacterId,
    this.relatedMaterialId,
    this.relatedGoalId,
    this.evidence,
    this.source,
    this.confidence = RecommendationConfidence.medium,
  });

  final String message;
  final String? reasonCode;
  final int importance; // 1=low .. 3=high
  final String? relatedCharacterId;
  final String? relatedMaterialId;
  final String? relatedGoalId;
  final String? evidence;
  final String? source;
  final RecommendationConfidence confidence;
}

class Recommendation {
  const Recommendation({
    required this.recommendationId,
    required this.recommendationType,
    required this.targetType,
    required this.targetId,
    this.priority = 0,
    this.score = 0.0,
    this.reasons = const [],
    this.expectedImpact,
    this.estimatedCost,
    this.estimatedResinCost,
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.usedDataSources = const [],
    this.generatedAt,
    this.expiresAt,
    this.ruleVersion,
  });

  final String recommendationId;
  final String recommendationType;
  final String targetType;
  final String targetId;
  final int priority;
  final double score;
  final List<RecommendationReason> reasons;
  final String? expectedImpact;
  final String? estimatedCost;
  final int? estimatedResinCost;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final List<String> usedDataSources;
  final DateTime? generatedAt;
  final DateTime? expiresAt;
  final String? ruleVersion;
}
