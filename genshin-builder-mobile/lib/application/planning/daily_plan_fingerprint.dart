import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/planning/daily_plan.dart';

/// Local fingerprint used to invalidate an adopted proposal when candidates,
/// progress, resin, or the game date changes. Raw plan text is not persisted.
String dailyPlanFingerprint(DailyPlan plan) {
  final candidates = [...plan.items]..sort((a, b) => a.id.compareTo(b.id));
  final encoded = jsonEncode({
    'date': _localDate(plan.date),
    'ruleVersion': plan.ruleVersion,
    'currentResin': plan.currentResin,
    'maxResin': plan.maxResin,
    'availableMinutes': plan.availableMinutes,
    'candidates': [
      for (final item in candidates)
        {
          'taskId': item.id,
          'type': item.type.name,
          'priority': item.priority,
          'currentLevel': item.currentLevel,
          'targetLevel': item.targetLevel,
          'estimatedResinCost': item.estimatedResinCost,
          'estimatedMinutes': item.estimatedMinutes,
          'availableToday': item.availableToday,
          'requiresResin': item.requiresResin,
          'bookmarked': item.bookmarked,
          'characterIds': [...item.characterIds]..sort(),
          'materialIds': [...item.materialIds]..sort(),
          'reasonFacts': item.reasons,
        },
    ],
  });
  return sha256.convert(utf8.encode(encoded)).toString();
}

String _localDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
