import '../recommendation/recommendation.dart';
import 'upgrade_option.dart';

/// Per-character priority within a saved team.
class TeamMemberGrowthPriority {
  const TeamMemberGrowthPriority({
    required this.characterId,
    this.characterName = '',
    this.priority = 0,
    this.score = 0.0,
    this.upgradeOptions = const [],
    this.reasons = const [],
    this.confidence = RecommendationConfidence.unknown,
  });

  final String characterId;
  /// Display name from master / snapshot; falls back to [characterId] in UI.
  final String characterName;
  final int priority;
  final double score;
  final List<UpgradeOption> upgradeOptions;
  final List<String> reasons;
  final RecommendationConfidence confidence;

  String get displayName {
    final name = characterName.trim();
    return name.isNotEmpty ? name : characterId;
  }
}

/// Priority report for a saved team.
class TeamGrowthPriorityReport {
  const TeamGrowthPriorityReport({
    required this.teamId,
    this.teamName = '',
    this.memberPriorities = const [],
    this.sharedMaterialOpportunities = const [],
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.generatedAt,
    this.ruleVersion = '1',
  });

  final String teamId;
  final String teamName;
  final List<TeamMemberGrowthPriority> memberPriorities;
  final List<String> sharedMaterialOpportunities;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final DateTime? generatedAt;
  final String ruleVersion;
}
