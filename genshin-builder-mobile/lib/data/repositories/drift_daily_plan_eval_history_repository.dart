import '../../domain/planning/daily_plan_eval_record.dart';
import '../../domain/repositories/daily_plan_eval_history_repository.dart';
import '../db/app_database_facade.dart';

class DriftDailyPlanEvalHistoryRepository
    implements DailyPlanEvalHistoryRepository {
  DriftDailyPlanEvalHistoryRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DailyPlanEvalRecord?> get({
    required String userId,
    required String localDate,
  }) async {
    try {
      final row = await _db.dailyPlanDao.evalGet(
        userId: userId,
        localDate: localDate,
      );
      if (row == null) return null;
      return DailyPlanEvalRecord(
        userId: row.userId,
        localDate: row.localDate,
        evaluatedAt: DateTime.fromMillisecondsSinceEpoch(row.evaluatedAt),
        notifiedAt: row.notifiedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.notifiedAt!),
        incompleteCount: row.incompleteCount,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasEvaluated({
    required String userId,
    required String localDate,
  }) async {
    final record = await get(userId: userId, localDate: localDate);
    return record != null;
  }

  @override
  Future<void> upsert(DailyPlanEvalRecord record) {
    return _db.dailyPlanDao.evalUpsert(
      userId: record.userId,
      localDate: record.localDate,
      evaluatedAtMs: record.evaluatedAt.millisecondsSinceEpoch,
      notifiedAtMs: record.notifiedAt?.millisecondsSinceEpoch,
      incompleteCount: record.incompleteCount,
    );
  }

  @override
  Future<int> pruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  }) {
    return _db.dailyPlanDao.evalPruneOlderThan(
      userId: userId,
      olderThanLocalDate: olderThanLocalDate,
    );
  }
}
