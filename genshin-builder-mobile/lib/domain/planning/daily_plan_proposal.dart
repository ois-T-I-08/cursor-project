enum DailyPlanRecommendationSource { deepseek, deterministicFallback }

class DailyPlanRecommendation {
  const DailyPlanRecommendation({
    required this.taskId,
    required this.priority,
    required this.reason,
    required this.suggestedMinutes,
  });

  final String taskId;
  final int priority;
  final String reason;
  final int suggestedMinutes;
}

class DailyPlanProposal {
  const DailyPlanProposal({
    required this.summary,
    required this.recommendations,
    required this.deferredTaskIds,
    required this.warnings,
    required this.source,
    required this.generatedAt,
    required this.inputHash,
    this.modelIdentifier,
  });

  final String summary;
  final List<DailyPlanRecommendation> recommendations;
  final List<String> deferredTaskIds;
  final List<String> warnings;
  final DailyPlanRecommendationSource source;
  final DateTime generatedAt;
  final String inputHash;
  final String? modelIdentifier;

  bool get isAiGenerated => source == DailyPlanRecommendationSource.deepseek;
  String get sourceLabel => isAiGenerated ? 'AI提案' : '通常提案';
}
