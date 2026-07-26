import '../../domain/planning/daily_plan_completion_record.dart';
import '../../domain/repositories/daily_plan_completion_repository.dart';
import '../db/app_database_facade.dart';

class DriftDailyPlanCompletionRepository
    implements DailyPlanCompletionRepository {
  DriftDailyPlanCompletionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Set<String>> getCompletedItemKeys({
    required String userId,
    required String localDate,
  }) async {
    try {
      final rows = await _db.dailyPlanDao.completionsForDate(
        userId: userId,
        localDate: localDate,
      );
      return rows.map((r) => r.itemKey).toSet();
    } catch (_) {
      // Corrupt / unexpected rows: treat as empty so UI / worker stay usable.
      return <String>{};
    }
  }

  @override
  Future<bool> isCompleted({
    required String userId,
    required String localDate,
    required String itemKey,
  }) async {
    try {
      final row = await _db.dailyPlanDao.completionGet(
        userId: userId,
        localDate: localDate,
        itemKey: itemKey,
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markCompleted(DailyPlanCompletionRecord record) {
    return _db.dailyPlanDao.completionUpsert(
      userId: record.userId,
      localDate: record.localDate,
      itemKey: record.itemKey,
      completedAtMs: record.completedAt.millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> unmarkCompleted({
    required String userId,
    required String localDate,
    required String itemKey,
  }) {
    return _db.dailyPlanDao.completionDelete(
      userId: userId,
      localDate: localDate,
      itemKey: itemKey,
    );
  }

  @override
  Future<int> pruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  }) {
    return _db.dailyPlanDao.completionsPruneOlderThan(
      userId: userId,
      olderThanLocalDate: olderThanLocalDate,
    );
  }
}
