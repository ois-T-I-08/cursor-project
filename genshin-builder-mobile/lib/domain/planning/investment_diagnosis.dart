import 'package:genshin_builder_mobile/domain/recommendation/recommendation.dart';

enum DiagnosisSeverity { info, warning, critical }

enum DiagnosisType {
  levelBelowGoal,
  ascensionBelowGoal,
  talentBelowGoal,
  weaponBelowGoal,
  weaponLevelLowVsCharacter,
  talentOverallLow,
  goalExceeded,
  artifactCompletionUnset,
  artifactCompletionLow,
  inventoryIncomplete,
}

class DiagnosisFinding {
  const DiagnosisFinding({
    required this.type,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.characterId,
    this.relatedGoalId,
    this.currentValue,
    this.targetValue,
    this.recommendation,
    this.confidence = RecommendationConfidence.medium,
    this.completeness = DataCompleteness.partial,
    this.missingData = const [],
    this.ruleVersion = '1',
  });

  final DiagnosisType type;
  final DiagnosisSeverity severity;
  final String title;
  final String explanation;
  final String characterId;
  final String? relatedGoalId;
  final String? currentValue;
  final String? targetValue;
  final String? recommendation;
  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final String ruleVersion;
}

class InvestmentDiagnosis {
  const InvestmentDiagnosis({
    required this.characterId,
    this.findings = const [],
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.generatedAt,
    this.ruleVersion = '1',
  });

  final String characterId;
  final List<DiagnosisFinding> findings;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get hasFindings => findings.isNotEmpty;
  List<DiagnosisFinding> get topFindings => findings.take(3).toList();
}
