import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/daily_plan_tables.dart';

part 'daily_plan_dao.g.dart';

@DriftAccessor(tables: [DailyPlanCompletions, DailyPlanEvalHistory])
class DailyPlanDao extends DatabaseAccessor<DriftAppDatabase>
    with _$DailyPlanDaoMixin {
  DailyPlanDao(super.db);

  Future<List<DailyPlanCompletion>> completionsForDate({
    required String userId,
    required String localDate,
  }) {
    return (select(dailyPlanCompletions)
          ..where(
            (t) => t.userId.equals(userId) & t.localDate.equals(localDate),
          ))
        .get();
  }

  Future<DailyPlanCompletion?> completionGet({
    required String userId,
    required String localDate,
    required String itemKey,
  }) {
    return (select(dailyPlanCompletions)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.localDate.equals(localDate) &
                t.itemKey.equals(itemKey),
          ))
        .getSingleOrNull();
  }

  Future<void> completionUpsert({
    required String userId,
    required String localDate,
    required String itemKey,
    required int completedAtMs,
  }) {
    return into(dailyPlanCompletions).insertOnConflictUpdate(
      DailyPlanCompletionsCompanion(
        userId: Value(userId),
        localDate: Value(localDate),
        itemKey: Value(itemKey),
        completedAt: Value(completedAtMs),
      ),
    );
  }

  Future<void> completionDelete({
    required String userId,
    required String localDate,
    required String itemKey,
  }) {
    return (delete(dailyPlanCompletions)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.localDate.equals(localDate) &
                t.itemKey.equals(itemKey),
          ))
        .go();
  }

  Future<int> completionsPruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  }) {
    return (delete(dailyPlanCompletions)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.localDate.isSmallerThanValue(olderThanLocalDate),
          ))
        .go();
  }

  Future<DailyPlanEvalHistoryData?> evalGet({
    required String userId,
    required String localDate,
  }) {
    return (select(dailyPlanEvalHistory)
          ..where(
            (t) => t.userId.equals(userId) & t.localDate.equals(localDate),
          ))
        .getSingleOrNull();
  }

  Future<void> evalUpsert({
    required String userId,
    required String localDate,
    required int evaluatedAtMs,
    int? notifiedAtMs,
    int? incompleteCount,
  }) {
    return into(dailyPlanEvalHistory).insertOnConflictUpdate(
      DailyPlanEvalHistoryCompanion(
        userId: Value(userId),
        localDate: Value(localDate),
        evaluatedAt: Value(evaluatedAtMs),
        notifiedAt: Value(notifiedAtMs),
        incompleteCount: Value(incompleteCount),
      ),
    );
  }

  Future<int> evalPruneOlderThan({
    required String userId,
    required String olderThanLocalDate,
  }) {
    return (delete(dailyPlanEvalHistory)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.localDate.isSmallerThanValue(olderThanLocalDate),
          ))
        .go();
  }
}
