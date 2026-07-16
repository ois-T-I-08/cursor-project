import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/db/app_database_facade.dart';
import '../../data/db/drift/app_database.dart';
import '../../data/hoyolab/hoyolab_home_disk_cache.dart';
import '../../data/repositories/drift_character_repository.dart';
import '../../data/repositories/drift_daily_plan_completion_repository.dart';
import '../../data/repositories/drift_daily_plan_eval_history_repository.dart';
import '../../data/repositories/drift_growth_goal_repository.dart';
import '../../data/repositories/drift_material_inventory_repository.dart';
import '../../data/repositories/drift_progress_repository.dart';
import '../../data/repositories/drift_team_repository.dart';
import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_completion_evaluator.dart';
import '../../domain/planning/daily_plan_eval_record.dart';
import '../../domain/planning/daily_plan_item_key.dart';
import '../account/build_account_snapshot_use_case.dart';
import '../planning/generate_daily_plan_use_case.dart';
import 'daily_plan_incomplete_notifier.dart';
import 'daily_plan_incomplete_scheduler.dart';
import 'daily_plan_notification_settings_store.dart';

/// Top-level WorkManager callback (no Riverpod).
@pragma('vm:entry-point')
void dailyPlanIncompleteCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await DailyPlanIncompleteWorker.run(inputData);
      return true;
    } catch (_) {
      // Avoid infinite retries on persistent failures; do not log secrets.
      debugPrint('daily_plan_incomplete: worker failed');
      return true;
    }
  });
}

/// Background eval for a pinned [targetLocalDate] (may run after midnight).
class DailyPlanIncompleteWorker {
  DailyPlanIncompleteWorker._();

  static Future<void> run(Map<String, dynamic>? inputData) async {
    final targetLocalDate = inputData?['targetLocalDate'] as String?;
    if (targetLocalDate == null || targetLocalDate.isEmpty) {
      debugPrint('daily_plan_incomplete: missing targetLocalDate');
      return;
    }

    DriftAppDatabase? drift;
    try {
      drift = await DriftAppDatabase.open(createInBackground: false);
      final db = AppDatabase.fromDrift(drift);
      final settingsStore = DailyPlanNotificationSettingsStore(
        AppDatabaseSettingsStore(db),
      );
      final scheduler = DailyPlanIncompleteScheduler();
      const notifier = DailyPlanIncompleteNotifier();
      final evalRepo = DriftDailyPlanEvalHistoryRepository(db);
      final completionRepo = DriftDailyPlanCompletionRepository(db);

      final enabled = await settingsStore.isIncompleteEnabled();
      final userId = (await db.getSetting('local_user_id'))?.trim() ?? '';
      if (!enabled || userId.isEmpty) {
        if (userId.isNotEmpty) {
          await scheduler.cancelForUser(
            userId: userId,
            settings: settingsStore,
          );
        }
        return;
      }

      final existing = await evalRepo.get(
        userId: userId,
        localDate: targetLocalDate,
      );
      if (existing != null) {
        await scheduler.rescheduleAfterEval(
          userId: userId,
          settings: settingsStore,
          evaluatedLocalDate: targetLocalDate,
        );
        return;
      }

      final osOk = await notifier.areNotificationsEnabled();
      final plan = await _loadPlan(
        db: db,
        userId: userId,
        targetLocalDate: targetLocalDate,
      );
      if (plan == null) {
        // Do not record a successful eval on fetch failure.
        debugPrint('daily_plan_incomplete: plan load failed');
        return;
      }

      final planKeys =
          plan.items.map(dailyPlanItemKey).toList(growable: false);
      final completed = await completionRepo.getCompletedItemKeys(
        userId: userId,
        localDate: targetLocalDate,
      );
      const evaluator = DailyPlanCompletionEvaluator();
      final incomplete = evaluator.countIncomplete(
        planItemKeys: planKeys,
        completedItemKeys: completed,
      );

      final now = DateTime.now();
      DateTime? notifiedAt;
      if (osOk && planKeys.isNotEmpty && incomplete > 0) {
        try {
          await notifier.showIncomplete(incompleteCount: incomplete);
          notifiedAt = now;
        } catch (_) {
          debugPrint('daily_plan_incomplete: show failed');
        }
      }

      await evalRepo.upsert(
        DailyPlanEvalRecord(
          userId: userId,
          localDate: targetLocalDate,
          evaluatedAt: now,
          notifiedAt: notifiedAt,
          incompleteCount: incomplete,
        ),
      );

      await _pruneOptional(userId, completionRepo, evalRepo);

      await scheduler.rescheduleAfterEval(
        userId: userId,
        settings: settingsStore,
        evaluatedLocalDate: targetLocalDate,
      );
    } finally {
      try {
        await drift?.close();
      } catch (_) {}
    }
  }

  static Future<DailyPlan?> _loadPlan({
    required AppDatabase db,
    required String userId,
    required String targetLocalDate,
  }) async {
    try {
      final parts = targetLocalDate.split('-');
      if (parts.length != 3) return null;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == null || month == null || day == null) return null;
      final date = DateTime(year, month, day);

      final snapshot = await BuildAccountSnapshotUseCase(
        characterRepo: DriftCharacterRepository(db),
        progressRepo: DriftProgressRepository(db),
        goalRepo: DriftGrowthGoalRepository(db),
        inventoryRepo: DriftMaterialInventoryRepository(db),
        teamRepo: DriftTeamRepository(db),
        userId: userId,
      )();

      return const GenerateDailyPlanUseCase()(
        userId: userId,
        snapshot: snapshot,
        date: date,
        weekday: date.weekday,
        generatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _pruneOptional(
    String userId,
    DriftDailyPlanCompletionRepository completionRepo,
    DriftDailyPlanEvalHistoryRepository evalRepo,
  ) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final olderThan = formatLocalDate(cutoff);
      await completionRepo.pruneOlderThan(
        userId: userId,
        olderThanLocalDate: olderThan,
      );
      await evalRepo.pruneOlderThan(
        userId: userId,
        olderThanLocalDate: olderThan,
      );
    } catch (_) {
      // Optional prune must never fail the worker.
    }
  }
}
