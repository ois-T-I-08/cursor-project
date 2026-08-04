import 'package:flutter/material.dart';

import '../../../domain/planning/daily_plan.dart';

String dailyPlanItemTypeLabel(DailyPlanItemType type) {
  switch (type) {
    case DailyPlanItemType.weekdayMaterial:
      return '曜日素材';
    case DailyPlanItemType.weeklyBoss:
      return '週ボス';
    case DailyPlanItemType.characterLevel:
      return 'レベル';
    case DailyPlanItemType.characterAscension:
      return '突破';
    case DailyPlanItemType.talent:
      return '天賦';
    case DailyPlanItemType.weapon:
      return '武器';
    case DailyPlanItemType.growthGoal:
      return '優先目標';
    case DailyPlanItemType.generalMaterial:
      return '素材集め';
  }
}

IconData dailyPlanItemTypeIcon(DailyPlanItemType type) {
  switch (type) {
    case DailyPlanItemType.weekdayMaterial:
      return Icons.calendar_today_outlined;
    case DailyPlanItemType.weeklyBoss:
      return Icons.shield_outlined;
    case DailyPlanItemType.characterLevel:
      return Icons.trending_up;
    case DailyPlanItemType.characterAscension:
      return Icons.north_east;
    case DailyPlanItemType.talent:
      return Icons.auto_stories_outlined;
    case DailyPlanItemType.weapon:
      return Icons.sports_martial_arts_outlined;
    case DailyPlanItemType.growthGoal:
      return Icons.flag_outlined;
    case DailyPlanItemType.generalMaterial:
      return Icons.inventory_2_outlined;
  }
}

String? dailyPlanLevelLabel(DailyPlanItem item) {
  if (item.currentLevel == null && item.targetLevel == null) return null;
  if (item.currentLevel != null && item.targetLevel != null) {
    return 'Lv.${item.currentLevel} → Lv.${item.targetLevel}';
  }
  if (item.targetLevel != null) return '目標 Lv.${item.targetLevel}';
  return '現在 Lv.${item.currentLevel}';
}

/// Converts local, structured facts into at most two user-facing badges.
/// AI free text is intentionally not inspected here.
List<String> dailyPlanReasonBadges(DailyPlanItem item) {
  final labels = <String>[];
  final localFacts = item.reasons.join(' ');
  final gap = _levelGap(item);

  if (item.availableToday &&
      (item.type == DailyPlanItemType.weekdayMaterial ||
          localFacts.contains('今日開放') ||
          localFacts.contains('本日入手可能'))) {
    labels.add('今日限定');
  }
  if (localFacts.contains('期限') || localFacts.contains('締切')) {
    labels.add('期限が近い');
  }
  if (gap != null && gap > 0 && gap <= 2) {
    labels.add('目標まであと少し');
  }
  if (item.requiresResin &&
      item.estimatedResinCost != null &&
      item.estimatedResinCost! <= 20) {
    labels.add('樹脂効率が高い');
  }
  if (item.priority >= 90) labels.add('育成効果が大きい');
  if (item.bookmarked) labels.add('ブックマーク中');
  if (item.materialIds.isNotEmpty &&
      item.missingData.isEmpty &&
      !item.requiresResin) {
    labels.add('素材が揃っている');
  }

  return labels.toSet().take(2).toList(growable: false);
}

String dailyPlanPrimaryReason(DailyPlanItem item) {
  final badges = dailyPlanReasonBadges(item);
  if (badges.contains('今日限定')) return '今日入手できる素材を優先します';
  if (badges.contains('期限が近い')) return '期限が近い育成を先に進めます';
  if (badges.contains('目標まであと少し')) return '目標まであと少しです';
  if (badges.contains('樹脂効率が高い')) return '少ない樹脂で進めやすい育成です';
  if (badges.contains('育成効果が大きい')) return '育成効果の大きい項目を優先します';
  if (badges.contains('ブックマーク中')) return 'ブックマーク中の育成です';
  if (badges.contains('素材が揃っている')) return '手元の素材で進められます';
  return '今日進めやすい育成から選びました';
}

String? dailyPlanGoalLabel(DailyPlanItem item) {
  final level = dailyPlanLevelLabel(item);
  if (level == null) return null;
  return '${dailyPlanItemTypeLabel(item.type)} $level';
}

String dailyPlanEstimateLabel(DailyPlanItem item, {int? suggestedMinutes}) {
  final parts = <String>[];
  if (item.estimatedResinCost != null) {
    parts.add('樹脂${item.estimatedResinCost}');
  } else if (item.requiresResin) {
    parts.add('樹脂量は確認中');
  }
  final minutes = suggestedMinutes ?? item.estimatedMinutes;
  if (minutes != null) parts.add('約$minutes分');
  return parts.isEmpty ? '所要量は詳細で確認' : '目安: ${parts.join(' / ')}';
}

String dailyPlanNextTaskMeta(DailyPlanItem item, {int? suggestedMinutes}) {
  final parts = <String>[];
  final gap = _levelGap(item);
  if (gap != null && gap > 0) {
    parts.add('あと$gapレベル');
  } else if (item.materialIds.isNotEmpty) {
    parts.add('あと素材${item.materialIds.length}種類');
  } else if (item.description != null && item.description!.trim().isNotEmpty) {
    parts.add(item.description!.trim());
  }

  final minutes = suggestedMinutes ?? item.estimatedMinutes;
  if (minutes != null) {
    parts.add('約$minutes分');
  } else if (item.estimatedResinCost != null) {
    parts.add('樹脂${item.estimatedResinCost}');
  }
  return parts.isEmpty ? '詳細を確認' : parts.take(2).join(' ・ ');
}

String dailyPlanDeferredReason(
  DailyPlanItem item, {
  required int? currentResin,
  required int? availableMinutes,
}) {
  final minutes = item.estimatedMinutes;
  if (availableMinutes != null &&
      minutes != null &&
      minutes > availableMinutes) {
    return '今日の時間に入りません';
  }
  final resin = item.estimatedResinCost;
  if (!item.availableToday ||
      (currentResin != null && resin != null && resin > currentResin)) {
    return '必要な素材または条件が不足しています';
  }
  if (item.missingData.isNotEmpty) {
    return '判断に必要な情報が不足しています';
  }
  final localFacts = item.reasons.join(' ');
  if (localFacts.contains('今日限定ではない') || localFacts.contains('後日')) {
    return '今日限定ではありません';
  }
  return 'ほかの育成を優先します';
}

int? _levelGap(DailyPlanItem item) {
  final current = item.currentLevel;
  final target = item.targetLevel;
  if (current == null || target == null || target <= current) return null;
  return target - current;
}
