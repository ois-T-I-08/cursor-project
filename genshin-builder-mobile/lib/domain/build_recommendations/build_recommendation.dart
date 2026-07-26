import '../character_stats.dart';

enum BuildRecommendationOrigin { singleVideo, merged }

class BuildRecommendationSource {
  const BuildRecommendationSource({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.sourceUrl,
    this.publishedAt,
  });

  final String videoId;
  final String title;
  final String channelTitle;
  final String sourceUrl;
  final DateTime? publishedAt;
}

class BuildRecommendationEvidence {
  const BuildRecommendationEvidence({
    required this.fieldPath,
    required this.exactVisibleText,
    required this.videoId,
    required this.startSeconds,
    required this.endSeconds,
  });

  final String fieldPath;
  final String exactVisibleText;
  final String videoId;
  final double startSeconds;
  final double endSeconds;
}

class BuildStatTarget {
  const BuildStatTarget({
    required this.stat,
    this.recommended,
    this.min,
    this.max,
    this.unit,
  });

  final StatKey stat;
  final double? recommended;
  final double? min;
  final double? max;
  final String? unit;
}

class CharacterBuildRecommendation {
  const CharacterBuildRecommendation({
    required this.characterId,
    required this.label,
    required this.origin,
    required this.overallConfidence,
    required this.targets,
    required this.substatPriority,
    required this.caveats,
    required this.sources,
    required this.evidence,
    this.lastVerifiedAt,
    this.publishedAt,
    this.role,
    this.teamArchetype,
  });

  final String characterId;
  final String label;
  final BuildRecommendationOrigin origin;
  final double overallConfidence;
  final List<BuildStatTarget> targets;
  final List<StatKey> substatPriority;
  final List<String> caveats;
  final List<BuildRecommendationSource> sources;
  final List<BuildRecommendationEvidence> evidence;
  final DateTime? lastVerifiedAt;
  final DateTime? publishedAt;
  final String? role;
  final String? teamArchetype;
}

enum BuildRecommendationFailure {
  notConfigured,
  notFound,
  timeout,
  networkError,
  invalidResponse,
}

class BuildRecommendationException implements Exception {
  const BuildRecommendationException(this.failure);

  final BuildRecommendationFailure failure;

  @override
  String toString() => 'BuildRecommendationException($failure)';
}

enum StatCompareVerdict { below, within, above, unknown }

StatCompareVerdict compareStatToTarget({
  required double current,
  required BuildStatTarget target,
}) {
  final min = target.min;
  final max = target.max;
  final recommended = target.recommended;
  if (min != null && max != null) {
    if (current < min) return StatCompareVerdict.below;
    if (current > max) return StatCompareVerdict.above;
    return StatCompareVerdict.within;
  }
  if (recommended != null) {
    final tol = recommended.abs() * 0.05 + 0.5;
    if (current < recommended - tol) return StatCompareVerdict.below;
    if (current > recommended + tol) return StatCompareVerdict.above;
    return StatCompareVerdict.within;
  }
  if (min != null) {
    return current < min ? StatCompareVerdict.below : StatCompareVerdict.within;
  }
  if (max != null) {
    return current > max ? StatCompareVerdict.above : StatCompareVerdict.within;
  }
  return StatCompareVerdict.unknown;
}

StatKey? parseGuideStatKey(String raw) {
  switch (raw) {
    case 'hp':
      return StatKey.hp;
    case 'atk':
      return StatKey.atk;
    case 'def':
      return StatKey.def;
    case 'em':
      return StatKey.em;
    case 'critRate':
      return StatKey.critRate;
    case 'critDmg':
      return StatKey.critDmg;
    case 'er':
      return StatKey.er;
    case 'healing':
      return StatKey.healing;
    case 'elemDmg':
      return StatKey.elemDmg;
    case 'physDmg':
      return StatKey.physDmg;
    default:
      return null;
  }
}
