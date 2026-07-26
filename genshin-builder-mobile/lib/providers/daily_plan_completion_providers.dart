import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/drift_daily_plan_completion_repository.dart';
import '../data/repositories/drift_daily_plan_eval_history_repository.dart';
import '../domain/planning/daily_plan_item_key.dart';
import '../domain/repositories/daily_plan_completion_repository.dart';
import '../domain/repositories/daily_plan_eval_history_repository.dart';
import 'app_providers.dart';

final dailyPlanCompletionRepoProvider =
    FutureProvider<DailyPlanCompletionRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftDailyPlanCompletionRepository(db);
});

final dailyPlanEvalHistoryRepoProvider =
    FutureProvider<DailyPlanEvalHistoryRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftDailyPlanEvalHistoryRepository(db);
});

/// Completed itemKeys for today's local calendar date (current user).
final dailyPlanTodayCompletionsProvider =
    FutureProvider<Set<String>>((ref) async {
  final repo = await ref.watch(dailyPlanCompletionRepoProvider.future);
  final userId = await ref.watch(localUserIdProvider.future);
  final localDate = formatLocalDate(DateTime.now());
  return repo.getCompletedItemKeys(userId: userId, localDate: localDate);
});
