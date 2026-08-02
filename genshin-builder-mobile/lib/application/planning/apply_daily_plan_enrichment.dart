import '../../domain/planning/daily_plan.dart';

/// Server-side enrichment result (reorder + Japanese reasons only).
class DailyPlanEnrichment {
  const DailyPlanEnrichment({
    required this.orderedItemIds,
    this.reasonsByItemId = const {},
    this.enriched = false,
    this.model,
  });

  final List<String> orderedItemIds;
  final Map<String, List<String>> reasonsByItemId;
  final bool enriched;
  final String? model;
}

/// Applies allowlisted reorder + reason overrides. Unknown IDs are ignored;
/// any local items missing from the server order are appended unchanged.
DailyPlan applyDailyPlanEnrichment(
  DailyPlan plan,
  DailyPlanEnrichment enrichment,
) {
  if (!enrichment.enriched || enrichment.orderedItemIds.isEmpty) {
    return plan;
  }

  final byId = {for (final item in plan.items) item.id: item};
  final seen = <String>{};
  final ordered = <DailyPlanItem>[];

  for (final id in enrichment.orderedItemIds) {
    final item = byId[id];
    if (item == null || !seen.add(id)) continue;
    final reasons = enrichment.reasonsByItemId[id];
    ordered.add(
      reasons == null || reasons.isEmpty
          ? item
          : DailyPlanItem(
            id: item.id,
            type: item.type,
            title: item.title,
            description: item.description,
            priority: item.priority,
            relatedGoalId: item.relatedGoalId,
            characterIds: item.characterIds,
            materialIds: item.materialIds,
            estimatedResinCost: item.estimatedResinCost,
            reasons: reasons.take(4).toList(),
            confidence: item.confidence,
            missingData: item.missingData,
          ),
    );
  }

  for (final item in plan.items) {
    if (seen.add(item.id)) ordered.add(item);
  }

  return DailyPlan(
    userId: plan.userId,
    date: plan.date,
    items: ordered,
    currentResin: plan.currentResin,
    maxResin: plan.maxResin,
    confidence: plan.confidence,
    completeness: plan.completeness,
    missingData: plan.missingData,
    generatedAt: plan.generatedAt,
    ruleVersion: '${plan.ruleVersion}+ds',
  );
}
