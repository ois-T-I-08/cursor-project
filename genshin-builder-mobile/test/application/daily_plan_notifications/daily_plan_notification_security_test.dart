import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_incomplete_scheduler.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_notification_ids.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_user_scope.dart';

void main() {
  test('notification strings contain no cookie/token/uid/db path', () {
    final title = DailyPlanNotificationIds.incompleteTitle;
    final body = DailyPlanNotificationIds.incompleteBody(3);
    final payload = DailyPlanNotificationIds.incompletePayload;
    final combined = '$title|$body|$payload';

    for (final forbidden in [
      'cookie',
      'ltoken',
      'ltoken_v2',
      'token',
      'uid=',
      'userId',
      '.db',
      'genshin_builder.db',
      'SecureStorage',
    ]) {
      expect(combined.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
    }
    expect(payload, 'route=/daily-plan');
  });

  test('unique work name uses non-reversible scope not raw userId', () {
    const userId = '11111111-1111-4111-8111-111111111111';
    final unique = DailyPlanIncompleteScheduler.uniqueNameFor(userId);
    expect(unique, startsWith('daily-plan-incomplete-v1-'));
    expect(unique, isNot(contains(userId)));
    expect(unique, contains(dailyPlanSafeUserScope(userId)));
    expect(dailyPlanSafeUserScope(userId).length, 12);
  });

  test('safeUserScope is stable and differs across users', () {
    expect(
      dailyPlanSafeUserScope('user-a'),
      dailyPlanSafeUserScope('user-a'),
    );
    expect(
      dailyPlanSafeUserScope('user-a'),
      isNot(dailyPlanSafeUserScope('user-b')),
    );
  });
}
