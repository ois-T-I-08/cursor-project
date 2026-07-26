import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'daily_plan_notification_ids.dart';
import 'daily_plan_notification_settings_store.dart';
import 'daily_plan_schedule_calculator.dart';
import 'daily_plan_user_scope.dart';

/// Registers / cancels P1-8C unique one-off WorkManager tasks.
class DailyPlanIncompleteScheduler {
  DailyPlanIncompleteScheduler({
    DailyPlanScheduleCalculator calculator = const DailyPlanScheduleCalculator(),
    DateTime Function()? now,
    Future<void> Function({
      required String uniqueName,
      required String taskName,
      required Map<String, dynamic> inputData,
      required Duration initialDelay,
    })? registerOneOff,
    Future<void> Function(String uniqueName)? cancelByUniqueName,
  })  : _calculator = calculator,
        _now = now ?? DateTime.now,
        _registerOneOff = registerOneOff ?? _defaultRegister,
        _cancelByUniqueName = cancelByUniqueName ?? _defaultCancel;

  final DailyPlanScheduleCalculator _calculator;
  final DateTime Function() _now;
  final Future<void> Function({
    required String uniqueName,
    required String taskName,
    required Map<String, dynamic> inputData,
    required Duration initialDelay,
  }) _registerOneOff;
  final Future<void> Function(String uniqueName) _cancelByUniqueName;

  static String uniqueNameFor(String userId) =>
      '${DailyPlanNotificationIds.uniqueNamePrefix}'
      '${dailyPlanSafeUserScope(userId)}';

  /// App start / resume / settings ON: schedule next (or catch-up) one-off.
  Future<void> ensureScheduled({
    required String userId,
    required DailyPlanNotificationSettingsStore settings,
    required bool todayAlreadyEvaluated,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (userId.isEmpty) return;
    final enabled = await settings.isIncompleteEnabled();
    if (!enabled) return;

    final decision = _calculator.computeNext(
      nowLocal: _now(),
      todayAlreadyEvaluated: todayAlreadyEvaluated,
    );
    await _registerDecision(
      userId: userId,
      settings: settings,
      decision: decision,
    );
  }

  /// After worker eval: register the following local 23:00.
  Future<void> rescheduleAfterEval({
    required String userId,
    required DailyPlanNotificationSettingsStore settings,
    required String evaluatedLocalDate,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (userId.isEmpty) return;
    final enabled = await settings.isIncompleteEnabled();
    if (!enabled) return;

    final decision = _calculator.computeAfterEval(
      nowLocal: _now(),
      evaluatedLocalDate: evaluatedLocalDate,
    );
    await _registerDecision(
      userId: userId,
      settings: settings,
      decision: decision,
    );
  }

  /// Cancel only this feature's unique work (never cancelAll — preserves P1-8B).
  Future<void> cancelForUser({
    required String userId,
    required DailyPlanNotificationSettingsStore settings,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final unique = uniqueNameFor(userId);
    try {
      await _cancelByUniqueName(unique);
    } catch (_) {
      debugPrint('daily_plan_incomplete: cancel unique work failed');
    }
    final previous = await settings.readLastUniqueWorkName();
    if (previous != null && previous.isNotEmpty && previous != unique) {
      try {
        await _cancelByUniqueName(previous);
      } catch (_) {
        debugPrint('daily_plan_incomplete: cancel previous unique work failed');
      }
    }
    await settings.clearLastUniqueWorkName();
  }

  Future<void> _registerDecision({
    required String userId,
    required DailyPlanNotificationSettingsStore settings,
    required DailyPlanScheduleDecision decision,
  }) async {
    final unique = uniqueNameFor(userId);
    final previous = await settings.readLastUniqueWorkName();
    if (previous != null && previous.isNotEmpty && previous != unique) {
      try {
        await _cancelByUniqueName(previous);
      } catch (_) {
        debugPrint('daily_plan_incomplete: cancel stale unique work failed');
      }
    }

    final delay = decision.initialDelay.isNegative
        ? Duration.zero
        : decision.initialDelay;

    // ExistingWorkPolicy.replace: TZ / settings changes must recalculate delay
    // instead of keeping a stale pending one-off for the old wall-clock target.
    await _registerOneOff(
      uniqueName: unique,
      taskName: DailyPlanNotificationIds.taskName,
      inputData: {
        'targetLocalDate': decision.targetLocalDate,
        'scheduledLocalDateTime':
            decision.scheduledLocalDateTime.toIso8601String(),
        'taskVersion': DailyPlanNotificationIds.taskVersion,
      },
      initialDelay: delay,
    );
    await settings.writeLastUniqueWorkName(unique);
  }

  static Future<void> _defaultRegister({
    required String uniqueName,
    required String taskName,
    required Map<String, dynamic> inputData,
    required Duration initialDelay,
  }) {
    return Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      inputData: inputData,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> _defaultCancel(String uniqueName) {
    return Workmanager().cancelByUniqueName(uniqueName);
  }
}
