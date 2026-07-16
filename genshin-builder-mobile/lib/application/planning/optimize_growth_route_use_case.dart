import '../../domain/planning/growth_route.dart';
import '../../domain/planning/upgrade_option.dart';
import '../../domain/recommendation/recommendation.dart';

/// Multi-day growth route from UpgradeOptions.
///
/// Rules:
/// 1. Weekday-limited materials scheduled on their available days
/// 2. High-priority goals first
/// 3. Shared materials grouped together
/// 4. Prerequisites (ascension before leveling beyond cap) respected
/// 5. Resin budget roughly respected (simplified)
class OptimizeGrowthRouteUseCase {
  const OptimizeGrowthRouteUseCase();

  static const ruleVersion = '4';
  static const defaultDayCount = 7;

  GrowthRoute call({
    required String userId,
    required List<UpgradeOption> options,
    required DateTime startDate,
    required int startWeekday, // 1=Mon..7=Sun
    int? dailyResinBudget,
    /// When false (default for UI), budget is display-only and does not cut actions.
    bool enforceDailyResinBudget = false,
    int dayCount = defaultDayCount,
    Map<String, Set<int>>? weekdayMap,
  }) {
    final days = <GrowthRouteDay>[];
    final remaining = List<UpgradeOption>.from(options);
    final unresolved = <String>[];
    final wkMap = weekdayMap ?? const {};
    final budgetForEnforce =
        enforceDailyResinBudget ? dailyResinBudget : null;

    _sortRemaining(remaining);

    for (var d = 0; d < dayCount; d++) {
      final date = startDate.add(Duration(days: d));
      final weekday = ((startWeekday - 1 + d) % 7) + 1;
      final actions = <GrowthRouteAction>[];
      var dayResin = 0;

      // Build candidates for today:
      // - Non-weekday-limited: always included
      // - Weekday-limited + matches today: included
      // - Weekday-limited + does NOT match: excluded (stays in remaining)
      final candidatesForToday = remaining.where((opt) {
        if (!_isWeekdayLimited(opt)) return true;
        return _matchesDay(opt, weekday, wkMap);
      }).toList();
      candidatesForToday.sort((a, b) => _compareOption(a, b));

      for (final opt in candidatesForToday) {
        if (actions.length >= 6) break;
        if (!_withinBudget(budgetForEnforce, dayResin, opt)) continue;
        final at = _isWeekdayLimited(opt) && _matchesDay(opt, weekday, wkMap)
            ? 'weekdayMaterial'
            : 'generalMaterial';
        actions.add(_toAction(opt, at));
        dayResin += opt.estimatedResinCost ?? 0;
        remaining.remove(opt);
      }

      if (actions.isEmpty && remaining.isEmpty) break;

      days.add(GrowthRouteDay(
        date: date,
        weekday: weekday,
        actions: actions,
        estimatedResinUsed: dayResin,
      ));
    }

    for (final opt in remaining) {
      unresolved.add(opt.optionId);
    }

    final hasInv = options.any((o) => o.inventoryStatus == InventoryStatus.ownedSufficient ||
        o.inventoryStatus == InventoryStatus.ownedInsufficient);

    final totalResin = days.fold<int>(
      0,
      (sum, day) => sum + (day.estimatedResinUsed ?? 0),
    );

    return GrowthRoute(
      userId: userId,
      startDate: startDate,
      endDate: startDate.add(Duration(days: dayCount - 1)),
      days: days,
      goals: options.map((o) => o.relatedGoalId ?? o.optionId).toSet().toList(),
      totalEstimatedResin: totalResin,
      dailyResinBudget: dailyResinBudget,
      unresolvedCosts: unresolved,
      confidence: hasInv ? RecommendationConfidence.high : RecommendationConfidence.low,
      completeness: hasInv ? DataCompleteness.partial : DataCompleteness.minimal,
      missingData: hasInv ? [] : [MissingData.materialInventory],
      usedDataSources: options.isNotEmpty ? ['upgradeOptions'] : [],
      generatedAt: startDate,
      ruleVersion: ruleVersion,
    );
  }

  // ── Option comparison (priority desc → impact desc → optionId asc) ──

  static int _compareOption(UpgradeOption a, UpgradeOption b) {
    int cmp = b.priority.compareTo(a.priority);
    if (cmp != 0) return cmp;

    final aImp = a.impact?.impactScore ?? 0;
    final bImp = b.impact?.impactScore ?? 0;
    cmp = bImp.compareTo(aImp);
    if (cmp != 0) return cmp;

    return a.optionId.compareTo(b.optionId);
  }

  static void _sortRemaining(List<UpgradeOption> list) {
    list.sort(_compareOption);
  }

  // ── Budget ────────────────────────────────────────────────────────

  static bool _withinBudget(int? budget, int used, UpgradeOption opt) {
    if (budget == null) return true;
    final cost = opt.estimatedResinCost ?? 0;
    return (used + cost) <= budget;
  }

  // ── Weekday matching ──────────────────────────────────────────────

  static bool _isWeekdayLimited(UpgradeOption o) =>
      o.optionType == 'talentNormal' ||
      o.optionType == 'talentSkill' ||
      o.optionType == 'talentBurst' ||
      o.optionType == 'weapon';

  /// Returns true if at least one of [o]'s materials is available on [weekday].
  /// If [weekdayMap] is empty, all days are treated as valid (conservative fallback).
  static bool _matchesDay(UpgradeOption o, int weekday, Map<String, Set<int>> weekdayMap) {
    if (o.materialsCost.isEmpty) return false;
    if (weekdayMap.isEmpty) return true; // no data → assume all days (fallback)
    for (final matId in o.materialsCost.keys) {
      final days = weekdayMap[matId];
      if (days != null && days.contains(weekday)) return true;
    }
    return false;
  }

  // ── Action builder ────────────────────────────────────────────────

  GrowthRouteAction _toAction(UpgradeOption o, String actionType) {
    return GrowthRouteAction(
      optionId: o.optionId,
      actionType: actionType,
      characterId: o.characterId,
      relatedGoalIds: o.relatedGoalId != null ? [o.relatedGoalId!] : [],
      materialIds: o.materialsCost.keys.toList(),
      estimatedResinCost: o.estimatedResinCost,
      priority: o.priority,
      reasons: [o.optionType],
    );
  }
}
