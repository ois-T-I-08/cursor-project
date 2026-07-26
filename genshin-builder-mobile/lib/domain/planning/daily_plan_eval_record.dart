/// History of a single day's incomplete-eval (and optional notification).
class DailyPlanEvalRecord {
  const DailyPlanEvalRecord({
    required this.userId,
    required this.localDate,
    required this.evaluatedAt,
    this.notifiedAt,
    this.incompleteCount,
  });

  final String userId;

  /// `YYYY-MM-DD` in the user's local calendar.
  final String localDate;
  final DateTime evaluatedAt;
  final DateTime? notifiedAt;
  final int? incompleteCount;

  bool get wasNotified => notifiedAt != null;
}
