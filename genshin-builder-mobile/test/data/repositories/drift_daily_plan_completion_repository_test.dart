import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database_facade.dart';
import 'package:genshin_builder_mobile/data/repositories/drift_daily_plan_completion_repository.dart';
import 'package:genshin_builder_mobile/data/repositories/drift_daily_plan_eval_history_repository.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_completion_record.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_eval_record.dart';

void main() {
  late AppDatabase db;
  late DriftDailyPlanCompletionRepository completionRepo;
  late DriftDailyPlanEvalHistoryRepository evalRepo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    completionRepo = DriftDailyPlanCompletionRepository(db);
    evalRepo = DriftDailyPlanEvalHistoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('mark / unmark / unique upsert / date isolation / user isolation', () async {
    final now = DateTime(2026, 7, 15, 12);
    await completionRepo.markCompleted(
      DailyPlanCompletionRecord(
        userId: 'u1',
        localDate: '2026-07-15',
        itemKey: 'k1',
        completedAt: now,
      ),
    );
    await completionRepo.markCompleted(
      DailyPlanCompletionRecord(
        userId: 'u1',
        localDate: '2026-07-15',
        itemKey: 'k1',
        completedAt: now.add(const Duration(minutes: 1)),
      ),
    );
    await completionRepo.markCompleted(
      DailyPlanCompletionRecord(
        userId: 'u1',
        localDate: '2026-07-16',
        itemKey: 'k1',
        completedAt: now,
      ),
    );
    await completionRepo.markCompleted(
      DailyPlanCompletionRecord(
        userId: 'u2',
        localDate: '2026-07-15',
        itemKey: 'k1',
        completedAt: now,
      ),
    );

    final u1today = await completionRepo.getCompletedItemKeys(
      userId: 'u1',
      localDate: '2026-07-15',
    );
    expect(u1today, {'k1'});
    expect(
      await completionRepo.isCompleted(
        userId: 'u1',
        localDate: '2026-07-15',
        itemKey: 'k1',
      ),
      isTrue,
    );

    final u1tomorrow = await completionRepo.getCompletedItemKeys(
      userId: 'u1',
      localDate: '2026-07-16',
    );
    expect(u1tomorrow, {'k1'});

    final u2 = await completionRepo.getCompletedItemKeys(
      userId: 'u2',
      localDate: '2026-07-15',
    );
    expect(u2, {'k1'});

    await completionRepo.unmarkCompleted(
      userId: 'u1',
      localDate: '2026-07-15',
      itemKey: 'k1',
    );
    expect(
      await completionRepo.getCompletedItemKeys(
        userId: 'u1',
        localDate: '2026-07-15',
      ),
      isEmpty,
    );
    expect(
      await completionRepo.getCompletedItemKeys(
        userId: 'u2',
        localDate: '2026-07-15',
      ),
      {'k1'},
    );
  });

  test('eval history unique per user+date and prune', () async {
    await evalRepo.upsert(
      DailyPlanEvalRecord(
        userId: 'u1',
        localDate: '2026-07-15',
        evaluatedAt: DateTime(2026, 7, 15, 23),
        incompleteCount: 2,
      ),
    );
    await evalRepo.upsert(
      DailyPlanEvalRecord(
        userId: 'u1',
        localDate: '2026-07-15',
        evaluatedAt: DateTime(2026, 7, 15, 23, 10),
        notifiedAt: DateTime(2026, 7, 15, 23, 10),
        incompleteCount: 1,
      ),
    );
    final row = await evalRepo.get(userId: 'u1', localDate: '2026-07-15');
    expect(row, isNotNull);
    expect(row!.incompleteCount, 1);
    expect(row.wasNotified, isTrue);
    expect(await evalRepo.hasEvaluated(userId: 'u1', localDate: '2026-07-15'), isTrue);
    expect(await evalRepo.hasEvaluated(userId: 'u1', localDate: '2026-07-16'), isFalse);

    await completionRepo.markCompleted(
      DailyPlanCompletionRecord(
        userId: 'u1',
        localDate: '2026-01-01',
        itemKey: 'old',
        completedAt: DateTime(2026, 1, 1),
      ),
    );
    final pruned = await completionRepo.pruneOlderThan(
      userId: 'u1',
      olderThanLocalDate: '2026-04-01',
    );
    expect(pruned, 1);
  });

  test('corrupt tolerance returns empty completed set', () async {
    // Missing tables would throw; openInMemory is healthy — exercise catch path
    // by using a closed DB after close (expect empty / false, not crash).
    await db.close();
    final closedRepo = DriftDailyPlanCompletionRepository(db);
    final keys = await closedRepo.getCompletedItemKeys(
      userId: 'u1',
      localDate: '2026-07-15',
    );
    expect(keys, isEmpty);
    // Avoid double-close in tearDown.
    db = await AppDatabase.openInMemory();
    completionRepo = DriftDailyPlanCompletionRepository(db);
    evalRepo = DriftDailyPlanEvalHistoryRepository(db);
  });
}
