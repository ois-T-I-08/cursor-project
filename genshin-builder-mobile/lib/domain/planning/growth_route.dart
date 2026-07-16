import '../recommendation/recommendation.dart';

/// A single day in a growth route.
class GrowthRouteDay {
  const GrowthRouteDay({
    required this.date,
    required this.weekday,
    this.availableResin,
    this.actions = const [],
    this.estimatedResinUsed,
    this.carriedOverResin,
    this.notes,
  });

  final DateTime date;
  final int weekday; // 1=Mon..7=Sun
  final int? availableResin;
  final List<GrowthRouteAction> actions;
  final int? estimatedResinUsed;
  final int? carriedOverResin;
  final String? notes;
}

/// A single task in a growth route.
class GrowthRouteAction {
  const GrowthRouteAction({
    required this.optionId,
    required this.actionType,
    this.characterId,
    this.relatedGoalIds = const [],
    this.materialIds = const [],
    this.estimatedResinCost,
    this.priority = 0,
    this.reasons = const [],
    this.status = 'planned',
  });

  final String optionId;
  final String actionType; // weekdayMaterial, generalMaterial, mora, expBook, boss
  final String? characterId;
  final List<String> relatedGoalIds;
  final List<String> materialIds;
  final int? estimatedResinCost;
  final int priority;
  final List<String> reasons;
  final String status; // planned, completed, skipped
}

/// Multi-day growth route.
class GrowthRoute {
  const GrowthRoute({
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.days = const [],
    this.goals = const [],
    this.totalEstimatedResin,
    this.dailyResinBudget,
    this.unresolvedCosts = const [],
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.usedDataSources = const [],
    this.generatedAt,
    this.ruleVersion = '1',
  });

  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final List<GrowthRouteDay> days;
  final List<String> goals;
  final int? totalEstimatedResin;
  /// Display-only budget (does not constrain scheduling).
  final int? dailyResinBudget;
  final List<String> unresolvedCosts;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final List<String> usedDataSources;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get isEmpty => days.every((d) => d.actions.isEmpty);
}
