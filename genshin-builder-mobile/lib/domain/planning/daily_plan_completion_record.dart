/// Persisted completion of one daily-plan item for a user on a local calendar day.
class DailyPlanCompletionRecord {
  const DailyPlanCompletionRecord({
    required this.userId,
    required this.localDate,
    required this.itemKey,
    required this.completedAt,
  });

  final String userId;

  /// `YYYY-MM-DD` in the user's local calendar.
  final String localDate;
  final String itemKey;
  final DateTime completedAt;
}
