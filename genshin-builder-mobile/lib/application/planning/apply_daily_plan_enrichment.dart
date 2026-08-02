import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_proposal.dart';

/// Applies a validated proposal to the existing local plan.
///
/// Item IDs and semantic completion keys stay unchanged. Unknown or duplicate
/// IDs are ignored, and generation alone never mutates progress or goals.
DailyPlan applyDailyPlanProposal(DailyPlan plan, DailyPlanProposal proposal) {
  if (proposal.recommendations.isEmpty) return plan;

  final byId = {for (final item in plan.items) item.id: item};
  final seen = <String>{};
  final ordered = <DailyPlanItem>[];

  for (final recommendation in proposal.recommendations) {
    final item = byId[recommendation.taskId];
    if (item == null || !seen.add(item.id) || !item.availableToday) continue;
    ordered.add(item.copyWith(reasons: [recommendation.reason]));
  }

  final deferred = proposal.deferredTaskIds.toSet();
  for (final item in plan.items) {
    if (!deferred.contains(item.id) && seen.add(item.id)) ordered.add(item);
  }
  for (final item in plan.items) {
    if (deferred.contains(item.id) && seen.add(item.id)) ordered.add(item);
  }

  return plan.copyWith(
    items: ordered,
    ruleVersion:
        '${plan.ruleVersion}+${proposal.isAiGenerated ? 'ai' : 'rules'}',
  );
}

@Deprecated('Use applyDailyPlanProposal')
DailyPlan applyDailyPlanEnrichment(
  DailyPlan plan,
  DailyPlanProposal proposal,
) => applyDailyPlanProposal(plan, proposal);
