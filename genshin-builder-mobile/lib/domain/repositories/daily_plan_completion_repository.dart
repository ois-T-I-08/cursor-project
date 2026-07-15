import '../planning/daily_plan_completion_record.dart';

abstract class DailyPlanCompletionRepository {
  Future<Set<String>> getCompletedItemKeys({
    required String userId,
    required String localDate,
  });

  Future<bool> isCompleted({
    required String userId,
    required String localDate,
    required String itemKey,
  });

  Future<void> markCompleted(DailyPlanCompletionRecord record);

  Future<void> unmarkCompleted({
    required String userId,
    required String localDate,
    required String itemKey,
  });

  /// Optional retention: delete rows older than [olderThanLocalDate] (exclusive).
  Future<int> pruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  });
}
