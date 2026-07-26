/// Fixed notification ids / channels / payloads for P1-8C (no secrets).
abstract final class DailyPlanNotificationIds {
  static const incomplete = 1003;
  static const incompleteChannelId = 'daily_plan_incomplete';
  static const incompleteChannelName = 'デイリー育成タスク';
  static const incompleteChannelDescription = '23時時点で未完了の育成タスクがあるときの通知';

  static const incompletePayload = 'route=/daily-plan';

  static const incompleteTitle = '今日の育成タスクが残っています';

  static String incompleteBody(int incompleteCount) =>
      '未完了のタスクが$incompleteCount件あります。今日の進捗を確認しましょう。';

  static const taskName = 'dailyPlanIncompleteEval';
  static const taskVersion = 1;
  static const uniqueNamePrefix = 'daily-plan-incomplete-v1-';

  /// Short delay for catch-up work after local 23:00.
  static const catchUpDelay = Duration(seconds: 2);
}
