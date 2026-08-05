import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_proposal.dart';
import 'daily_plan_fingerprint.dart';

/// Revalidates the proposal against the plan snapshot at the adoption boundary.
bool canAdoptDailyPlanProposal(DailyPlan plan, DailyPlanProposal proposal) {
  if (proposal.schemaVersion != dailyPlanProposalSchemaVersion ||
      proposal.proposalFingerprint != dailyPlanFingerprint(plan) ||
      proposal.recommendations.isEmpty) {
    return false;
  }

  final byId = {for (final item in plan.items) item.id: item};
  final seenIds = <String>{};
  final seenPriorities = <int>{};
  var remainingResin = plan.currentResin;
  var remainingMinutes = plan.availableMinutes;
  final recommendations = [...proposal.recommendations]
    ..sort((a, b) => a.priority.compareTo(b.priority));
  for (final recommendation in recommendations) {
    final item = byId[recommendation.taskId];
    if (item == null ||
        !item.availableToday ||
        !seenIds.add(item.id) ||
        !seenPriorities.add(recommendation.priority) ||
        recommendation.priority < 1 ||
        recommendation.priority > 5 ||
        recommendation.suggestedMinutes < 5 ||
        recommendation.suggestedMinutes > 180 ||
        recommendation.reason.trim().isEmpty ||
        item.estimatedMinutes != null &&
            recommendation.suggestedMinutes > item.estimatedMinutes!) {
      return false;
    }
    final resinCost = item.estimatedResinCost;
    if (item.requiresResin && remainingResin == 0 ||
        remainingResin != null &&
            resinCost != null &&
            resinCost > remainingResin ||
        remainingMinutes != null &&
            recommendation.suggestedMinutes > remainingMinutes) {
      return false;
    }
    if (remainingResin != null && resinCost != null) {
      remainingResin -= resinCost;
    }
    if (remainingMinutes != null) {
      remainingMinutes -= recommendation.suggestedMinutes;
    }
  }

  final deferred = <String>{};
  for (final taskId in proposal.deferredTaskIds) {
    if (!byId.containsKey(taskId) ||
        seenIds.contains(taskId) ||
        !deferred.add(taskId)) {
      return false;
    }
  }
  return true;
}

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
