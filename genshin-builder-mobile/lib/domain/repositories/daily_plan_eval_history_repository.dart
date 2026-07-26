import '../planning/daily_plan_eval_record.dart';

abstract class DailyPlanEvalHistoryRepository {
  Future<DailyPlanEvalRecord?> get({
    required String userId,
    required String localDate,
  });

  Future<bool> hasEvaluated({
    required String userId,
    required String localDate,
  });

  Future<void> upsert(DailyPlanEvalRecord record);

  Future<int> pruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  });
}
