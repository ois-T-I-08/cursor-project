import 'package:drift/drift.dart';

/// Per-user, per-local-date completion of a daily-plan item (Option D).
///
/// Growth is unbounded over time; callers may prune rows older than ~90 days.
class DailyPlanCompletions extends Table {
  TextColumn get userId => text()();
  TextColumn get localDate => text()();
  TextColumn get itemKey => text()();
  IntColumn get completedAt => integer()();

  @override
  Set<Column> get primaryKey => {userId, localDate, itemKey};
}

/// Per-user, per-local-date eval / notify history for P1-8C.
///
/// Growth is unbounded over time; callers may prune rows older than ~90 days.
class DailyPlanEvalHistory extends Table {
  TextColumn get userId => text()();
  TextColumn get localDate => text()();
  IntColumn get evaluatedAt => integer()();
  IntColumn get notifiedAt => integer().nullable()();
  IntColumn get incompleteCount => integer().nullable()();

  @override
  Set<Column> get primaryKey => {userId, localDate};
}
