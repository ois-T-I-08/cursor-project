import '../../domain/planning/daily_plan_item_key.dart';
import 'daily_plan_notification_ids.dart';

/// Pure schedule decision for the next P1-8C one-off WorkManager task.
class DailyPlanScheduleDecision {
  const DailyPlanScheduleDecision({
    required this.targetLocalDate,
    required this.scheduledLocalDateTime,
    required this.initialDelay,
    required this.isCatchUp,
  });

  final String targetLocalDate;
  final DateTime scheduledLocalDateTime;
  final Duration initialDelay;
  final bool isCatchUp;
}

/// Computes next local 23:00 one-off (or catch-up) without side effects.
class DailyPlanScheduleCalculator {
  const DailyPlanScheduleCalculator();

  DailyPlanScheduleDecision computeNext({
    required DateTime nowLocal,
    required bool todayAlreadyEvaluated,
  }) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final today2300 = DateTime(today.year, today.month, today.day, 23);
    final todayKey = formatLocalDate(today);

    if (nowLocal.isBefore(today2300)) {
      return DailyPlanScheduleDecision(
        targetLocalDate: todayKey,
        scheduledLocalDateTime: today2300,
        initialDelay: today2300.difference(nowLocal),
        isCatchUp: false,
      );
    }

    if (!todayAlreadyEvaluated) {
      return DailyPlanScheduleDecision(
        targetLocalDate: todayKey,
        scheduledLocalDateTime: today2300,
        initialDelay: DailyPlanNotificationIds.catchUpDelay,
        isCatchUp: true,
      );
    }

    final tomorrow = today.add(const Duration(days: 1));
    final tomorrow2300 =
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23);
    return DailyPlanScheduleDecision(
      targetLocalDate: formatLocalDate(tomorrow),
      scheduledLocalDateTime: tomorrow2300,
      initialDelay: tomorrow2300.difference(nowLocal),
      isCatchUp: false,
    );
  }

  /// After a successful eval for [evaluatedLocalDate], schedule the next 23:00.
  DailyPlanScheduleDecision computeAfterEval({
    required DateTime nowLocal,
    required String evaluatedLocalDate,
  }) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final todayKey = formatLocalDate(today);
    final today2300 = DateTime(today.year, today.month, today.day, 23);

    if (evaluatedLocalDate == todayKey || !nowLocal.isBefore(today2300)) {
      final tomorrow = today.add(const Duration(days: 1));
      final tomorrow2300 =
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23);
      return DailyPlanScheduleDecision(
        targetLocalDate: formatLocalDate(tomorrow),
        scheduledLocalDateTime: tomorrow2300,
        initialDelay: tomorrow2300.difference(nowLocal),
        isCatchUp: false,
      );
    }

    return DailyPlanScheduleDecision(
      targetLocalDate: todayKey,
      scheduledLocalDateTime: today2300,
      initialDelay: today2300.difference(nowLocal),
      isCatchUp: false,
    );
  }
}
