import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/drift_daily_plan_eval_history_repository.dart';
import '../../domain/planning/daily_plan_item_key.dart';
import '../../domain/repositories/daily_plan_eval_history_repository.dart';
import 'daily_plan_incomplete_notifier.dart';
import 'daily_plan_incomplete_scheduler.dart';
import 'daily_plan_notification_settings_store.dart';

/// Foreground orchestration for P1-8C schedule / cancel (no WorkManager cancelAll).
class DailyPlanNotificationCoordinator {
  DailyPlanNotificationCoordinator({
    required DailyPlanNotificationSettingsStore settings,
    required DailyPlanEvalHistoryRepository evalHistory,
    DailyPlanIncompleteScheduler? scheduler,
    DailyPlanIncompleteNotifier notifier =
        const DailyPlanIncompleteNotifier(),
    DateTime Function()? now,
  })  : _settings = settings,
        _evalHistory = evalHistory,
        _scheduler = scheduler ?? DailyPlanIncompleteScheduler(),
        _notifier = notifier,
        _now = now ?? DateTime.now;

  final DailyPlanNotificationSettingsStore _settings;
  final DailyPlanEvalHistoryRepository _evalHistory;
  final DailyPlanIncompleteScheduler _scheduler;
  final DailyPlanIncompleteNotifier _notifier;
  final DateTime Function() _now;

  Future<void> ensureScheduledForUser(String userId) async {
    if (userId.isEmpty) return;
    final today = formatLocalDate(_now());
    final evaluated = await _evalHistory.hasEvaluated(
      userId: userId,
      localDate: today,
    );
    await _scheduler.ensureScheduled(
      userId: userId,
      settings: _settings,
      todayAlreadyEvaluated: evaluated,
    );
  }

  Future<void> onEnabled({required String userId}) async {
    await _settings.setIncompleteEnabled(true);
    await ensureScheduledForUser(userId);
  }

  Future<void> onDisabled({required String userId}) async {
    await _settings.setIncompleteEnabled(false);
    await _scheduler.cancelForUser(userId: userId, settings: _settings);
    await _notifier.cancel();
  }

  /// OFF / logout / user switch — cancel unique work only (not P1-8B).
  Future<void> cancelForLogoutOrUserSwitch(String userId) async {
    try {
      await _scheduler.cancelForUser(userId: userId, settings: _settings);
      await _notifier.cancel();
    } catch (_) {
      debugPrint('daily_plan_incomplete: logout cancel failed');
    }
  }
}

/// Fire-and-forget schedule helper for lifecycle hooks.
void ensureDailyPlanIncompleteScheduledUnawaited(
  DailyPlanNotificationCoordinator coordinator,
  String userId,
) {
  unawaited(() async {
    try {
      await coordinator.ensureScheduledForUser(userId);
    } catch (_) {
      debugPrint('daily_plan_incomplete: ensureScheduled failed');
    }
  }());
}

/// Convenience factory used by providers / worker-adjacent code.
DailyPlanNotificationCoordinator buildDailyPlanNotificationCoordinator({
  required DailyPlanNotificationSettingsStore settings,
  required DriftDailyPlanEvalHistoryRepository evalHistory,
  DailyPlanIncompleteScheduler? scheduler,
}) {
  return DailyPlanNotificationCoordinator(
    settings: settings,
    evalHistory: evalHistory,
    scheduler: scheduler,
  );
}
