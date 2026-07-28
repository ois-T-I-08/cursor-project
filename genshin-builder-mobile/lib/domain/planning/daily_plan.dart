import '../recommendation/recommendation.dart';

/// A daily plan generated from growth goals, resin, and weekday materials.
class DailyPlan {
  const DailyPlan({
    required this.userId,
    required this.date,
    this.items = const [],
    this.currentResin,
    this.maxResin,
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.generatedAt,
    this.ruleVersion = '1',
  });

  final String userId;
  final DateTime date;
  final List<DailyPlanItem> items;
  final int? currentResin;
  final int? maxResin;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get isEmpty => items.isEmpty;
  List<DailyPlanItem> get topItems => items.take(3).toList();
}

enum DailyPlanItemType {
  weekdayMaterial,
  weeklyBoss,
  growthGoal,
  generalMaterial,
}

class DailyPlanItem {
  const DailyPlanItem({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.priority = 0,
    this.relatedGoalId,
    this.characterIds = const [],
    this.materialIds = const [],
    this.estimatedResinCost,
    this.reasons = const [],
    this.confidence = RecommendationConfidence.medium,
    this.missingData = const [],
  });

  final String id;
  final DailyPlanItemType type;
  final String title;
  final String? description;
  final int priority;
  final String? relatedGoalId;
  final List<String> characterIds;
  final List<String> materialIds;
  final int? estimatedResinCost;
  final List<String> reasons;
  final RecommendationConfidence confidence;
  final List<MissingData> missingData;
}
