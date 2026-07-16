import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/growth_route_request.dart';

/// Default daily resin budget when HoYoLAB max resin is unknown.
const kDefaultDailyResinBudget = 160;

GrowthRouteRequest buildGrowthRouteRequest(
  DailyPlan plan,
  DateTime startDate,
) {
  final normalizedDate =
      DateTime(startDate.year, startDate.month, startDate.day);
  return GrowthRouteRequest(
    goalIds: plan.items
        .map((item) => item.relatedGoalId)
        .whereType<String>()
        .toSet()
        .toList(),
    startDate: normalizedDate,
    startWeekday: normalizedDate.weekday,
    dailyResinBudget: plan.maxResin ?? kDefaultDailyResinBudget,
  );
}
