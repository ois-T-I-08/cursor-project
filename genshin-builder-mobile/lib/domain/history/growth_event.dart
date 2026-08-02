/// Growth event recorded when character build state changes.
///
/// Deduplication: events with the same [dedupKey] must not be stored twice.
library;

enum GrowthEventType {
  characterLevelChanged,
  ascensionChanged,
  talentNormalChanged,
  talentSkillChanged,
  talentBurstChanged,
  weaponChanged,
  weaponLevelChanged,
  weaponRefinementChanged,
  artifactCompletionChanged,
  growthGoalCompleted,
  teamCompleted,
  accountHealthScoreChanged,
}

/// Cursor for paginating growth events.
class GrowthEventCursor {
  const GrowthEventCursor({required this.observedAt, required this.eventId});

  final DateTime observedAt;
  final String eventId;
}

class GrowthEvent {
  const GrowthEvent({
    required this.eventId,
    required this.userId,
    required this.characterId,
    required this.eventType,
    this.beforeValue,
    this.afterValue,
    this.source,
    required this.observedAt,
    this.createdAt,
    required this.dedupKey,
  });

  final String eventId;
  final String userId;
  final String characterId;
  final GrowthEventType eventType;
  final String? beforeValue;
  final String? afterValue;
  final String? source;
  final DateTime observedAt;
  final DateTime? createdAt;
  final String dedupKey;

  /// Generate a stable deduplication key for value-level changes.
  static String makeDedupKey({
    required String userId,
    required String characterId,
    required GrowthEventType eventType,
    required DateTime observedAt,
  }) {
    return '$userId:$characterId:${eventType.name}:${observedAt.toIso8601String()}';
  }

  /// Generate a deduplication key from value-level before/after.
  static String makeValueDedupKey({
    required String userId,
    required String characterId,
    required GrowthEventType eventType,
    required String before,
    required String after,
  }) {
    return '$userId:$characterId:${eventType.name}:$before->$after';
  }
}
