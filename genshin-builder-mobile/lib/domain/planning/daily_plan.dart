import '../recommendation/recommendation.dart';

/// A daily plan generated from growth goals, resin, and weekday materials.
class DailyPlan {
  const DailyPlan({
    required this.userId,
    required this.date,
    this.items = const [],
    this.currentResin,
    this.maxResin,
    this.availableMinutes,
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
  final int? availableMinutes;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get isEmpty => items.isEmpty;
  List<DailyPlanItem> get topItems => items.take(3).toList();

  DailyPlan copyWith({List<DailyPlanItem>? items, String? ruleVersion}) {
    return DailyPlan(
      userId: userId,
      date: date,
      items: items ?? this.items,
      currentResin: currentResin,
      maxResin: maxResin,
      availableMinutes: availableMinutes,
      confidence: confidence,
      completeness: completeness,
      missingData: missingData,
      generatedAt: generatedAt,
      ruleVersion: ruleVersion ?? this.ruleVersion,
    );
  }
}

enum DailyPlanItemType {
  weekdayMaterial,
  weeklyBoss,
  characterLevel,
  characterAscension,
  talent,
  weapon,
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
    this.estimatedMinutes,
    this.currentLevel,
    this.targetLevel,
    this.availableToday = true,
    this.requiresResin = false,
    this.bookmarked = false,
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
  final int? estimatedMinutes;
  final int? currentLevel;
  final int? targetLevel;
  final bool availableToday;
  final bool requiresResin;
  final bool bookmarked;
  final List<String> reasons;
  final RecommendationConfidence confidence;
  final List<MissingData> missingData;

  DailyPlanItem copyWith({int? priority, List<String>? reasons}) {
    return DailyPlanItem(
      id: id,
      type: type,
      title: title,
      description: description,
      priority: priority ?? this.priority,
      relatedGoalId: relatedGoalId,
      characterIds: characterIds,
      materialIds: materialIds,
      estimatedResinCost: estimatedResinCost,
      estimatedMinutes: estimatedMinutes,
      currentLevel: currentLevel,
      targetLevel: targetLevel,
      availableToday: availableToday,
      requiresResin: requiresResin,
      bookmarked: bookmarked,
      reasons: reasons ?? this.reasons,
      confidence: confidence,
      missingData: missingData,
    );
  }
}
