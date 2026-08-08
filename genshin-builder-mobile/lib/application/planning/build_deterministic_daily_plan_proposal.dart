import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_proposal.dart';
import 'daily_plan_fingerprint.dart';

DailyPlanProposal buildDeterministicDailyPlanProposal(
  DailyPlan plan, {
  DateTime? generatedAt,
}) {
  var resin = plan.currentResin;
  var minutes = plan.availableMinutes;
  final recommendations = <DailyPlanRecommendation>[];
  final deferred = <String>[];

  for (final item in plan.items) {
    if (recommendations.length >= 5 || !item.availableToday) {
      deferred.add(item.id);
      continue;
    }
    final cost = item.estimatedResinCost;
    final suggested = item.estimatedMinutes ?? 20;
    if (item.requiresResin && resin == 0 ||
        resin != null && cost != null && cost > resin ||
        minutes != null && suggested > minutes) {
      deferred.add(item.id);
      continue;
    }
    recommendations.add(
      DailyPlanRecommendation(
        taskId: item.id,
        priority: recommendations.length + 1,
        reason: item.reasons.isNotEmpty ? item.reasons.first : '既存の優先度に基づく候補です',
        suggestedMinutes: suggested.clamp(5, 180),
      ),
    );
    if (resin != null && cost != null) resin -= cost;
    if (minutes != null) minutes -= suggested;
  }
  for (final item in plan.items) {
    if (!recommendations.any((entry) => entry.taskId == item.id) &&
        !deferred.contains(item.id)) {
      deferred.add(item.id);
    }
  }

  return DailyPlanProposal(
    summary:
        recommendations.isEmpty
            ? '今日実行できる候補を確認できませんでした'
            : '今日実行できる候補を、入手日と既存優先度から並べました',
    recommendations: recommendations,
    deferredTaskIds: deferred,
    warnings: [
      if (plan.currentResin == null) '樹脂残量を取得できないため、樹脂予算は最終確認してください',
      if (plan.availableMinutes == null) '利用可能時間が未設定のため、所要時間は目安です',
    ],
    source: DailyPlanRecommendationSource.deterministicFallback,
    generatedAt: generatedAt ?? DateTime.now(),
    inputHash: dailyPlanFingerprint(plan),
    proposalFingerprint: dailyPlanFingerprint(plan),
  );
}
