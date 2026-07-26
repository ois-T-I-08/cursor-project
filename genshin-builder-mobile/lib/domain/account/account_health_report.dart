import '../recommendation/recommendation.dart';

enum HealthRating { excellent, good, average, poor, unknown }

/// A single category in the account health report.
class AccountHealthCategory {
  const AccountHealthCategory({
    required this.name,
    required this.score,
    this.maxScore = 100,
    this.weight = 1.0,
    this.evaluated = true,
    this.reasons = const [],
    this.evidenceCount = 0,
    this.missingData = const [],
    this.improvementHints = const [],
  });

  final String name;
  final double score;
  final double maxScore;
  final double weight;
  final bool evaluated;
  final List<String> reasons;
  final int evidenceCount;
  final List<MissingData> missingData;
  final List<String> improvementHints;

  double get normalizedScore => evaluated ? (score / maxScore * 100).clamp(0, 100) : 0;
}

/// Account health report generated from an [AccountSnapshot].
class AccountHealthReport {
  const AccountHealthReport({
    this.totalScore,
    this.rating = HealthRating.unknown,
    this.categories = const [],
    this.strengths = const [],
    this.improvementCandidates = const [],
    this.dataCoverage = '不明',
    this.confidence = RecommendationConfidence.unknown,
    this.completeness = DataCompleteness.unavailable,
    this.missingData = const [],
    this.generatedAt,
    this.ruleVersion = '1',
  });

  /// Overall health score (null = unevaluable). Only includes evaluated categories.
  final double? totalScore;
  final HealthRating rating;
  final List<AccountHealthCategory> categories;
  final List<String> strengths;
  final List<String> improvementCandidates;

  /// Data coverage level (separate from health score).
  final String dataCoverage;

  final RecommendationConfidence confidence;
  final DataCompleteness completeness;
  final List<MissingData> missingData;
  final DateTime? generatedAt;
  final String ruleVersion;

  bool get isEvaluable => totalScore != null;
  int get evaluatedCategoryCount => categories.where((c) => c.evaluated).length;

  static HealthRating scoreToRating(double score) {
    if (score >= 80) return HealthRating.excellent;
    if (score >= 60) return HealthRating.good;
    if (score >= 40) return HealthRating.average;
    if (score >= 0) return HealthRating.poor;
    return HealthRating.unknown;
  }
}
