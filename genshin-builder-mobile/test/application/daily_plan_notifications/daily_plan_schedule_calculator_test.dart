import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_notification_ids.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_schedule_calculator.dart';

void main() {
  const calculator = DailyPlanScheduleCalculator();

  test('before 23:00 schedules today with correct delay and target', () {
    final now = DateTime(2026, 7, 15, 10, 0);
    final decision = calculator.computeNext(
      nowLocal: now,
      todayAlreadyEvaluated: false,
    );
    expect(decision.targetLocalDate, '2026-07-15');
    expect(decision.scheduledLocalDateTime, DateTime(2026, 7, 15, 23));
    expect(decision.initialDelay, const Duration(hours: 13));
    expect(decision.isCatchUp, isFalse);
  });

  test('past 23:00 without eval → catch-up for today', () {
    final now = DateTime(2026, 7, 15, 23, 30);
    final decision = calculator.computeNext(
      nowLocal: now,
      todayAlreadyEvaluated: false,
    );
    expect(decision.targetLocalDate, '2026-07-15');
    expect(decision.scheduledLocalDateTime, DateTime(2026, 7, 15, 23));
    expect(decision.initialDelay, DailyPlanNotificationIds.catchUpDelay);
    expect(decision.isCatchUp, isTrue);
  });

  test('past 23:00 with eval → tomorrow 23:00', () {
    final now = DateTime(2026, 7, 15, 23, 30);
    final decision = calculator.computeNext(
      nowLocal: now,
      todayAlreadyEvaluated: true,
    );
    expect(decision.targetLocalDate, '2026-07-16');
    expect(decision.scheduledLocalDateTime, DateTime(2026, 7, 16, 23));
    expect(decision.isCatchUp, isFalse);
  });

  test('late execution still uses pinned targetLocalDate from schedule', () {
    // Schedule was for 2026-07-15 23:00; runs at 23:10 or next-day 00:01 —
    // targetLocalDate remains the registered value (not recomputed from now).
    final scheduled = calculator.computeNext(
      nowLocal: DateTime(2026, 7, 15, 22, 0),
      todayAlreadyEvaluated: false,
    );
    expect(scheduled.targetLocalDate, '2026-07-15');

    // Worker must evaluate inputData target even if now is next day.
    const pinned = '2026-07-15';
    final runAt2310 = DateTime(2026, 7, 15, 23, 10);
    final runAt0001 = DateTime(2026, 7, 16, 0, 1);
    expect(pinned, isNot(equals(_format(runAt0001))));
    expect(pinned, _format(DateTime(runAt2310.year, runAt2310.month, runAt2310.day)));
  });

  test('afterEval for today schedules tomorrow', () {
    final decision = calculator.computeAfterEval(
      nowLocal: DateTime(2026, 7, 15, 23, 5),
      evaluatedLocalDate: '2026-07-15',
    );
    expect(decision.targetLocalDate, '2026-07-16');
    expect(decision.scheduledLocalDateTime, DateTime(2026, 7, 16, 23));
  });
}

String _format(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
