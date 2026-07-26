import 'daily_plan.dart';

/// Deterministic item key from semantic fields only (not title / translated text).
///
/// Encoding is stable across UI, repositories, and background workers.
String dailyPlanItemKey(DailyPlanItem item) {
  final chars = List<String>.from(item.characterIds)..sort();
  final mats = List<String>.from(item.materialIds)..sort();
  final goal = item.relatedGoalId ?? '';
  return 'v1|type=${item.type.name}|goal=$goal|'
      'chars=${chars.join(',')}|mats=${mats.join(',')}';
}

/// Format a calendar day as `YYYY-MM-DD` in the given local [date] components.
String formatLocalDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
