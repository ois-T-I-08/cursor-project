import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_proposal.dart';

final _taskIdPattern = RegExp(r'^[A-Za-z0-9:_|.\-]{1,128}$');
final _hashPattern = RegExp(r'^[a-f0-9]{64}$');
final _forbiddenFormat = RegExp(
  r'https?://|www\.|<[^>]*>|\[[^\]]+\]\([^)]*\)|[*_`#]',
  caseSensitive: false,
);

DailyPlanProposal? parseDailyPlanProposal(
  Object? value, {
  Set<String>? allowedTaskIds,
  DailyPlan? plan,
}) {
  final effectiveAllowed =
      plan?.items.map((item) => item.id).toSet() ?? allowedTaskIds;
  if (value is! Map) return null;
  final map = Map<String, dynamic>.from(value);
  if (!_hasOnlyKeys(map, const {
    'schemaVersion',
    'summary',
    'recommendations',
    'deferredTaskIds',
    'warnings',
    'source',
    'generatedAt',
    'inputHash',
    'proposalFingerprint',
    'modelIdentifier',
  })) {
    return null;
  }

  final summary = _safeText(map['summary']);
  final generatedAt = DateTime.tryParse('${map['generatedAt'] ?? ''}');
  final inputHash = '${map['inputHash'] ?? ''}';
  final proposalFingerprint = '${map['proposalFingerprint'] ?? ''}';
  final source = switch (map['source']) {
    'deepseek' => DailyPlanRecommendationSource.deepseek,
    'deterministic_fallback' =>
      DailyPlanRecommendationSource.deterministicFallback,
    _ => null,
  };
  if (map['schemaVersion'] != dailyPlanProposalSchemaVersion ||
      summary == null ||
      generatedAt == null ||
      !_hashPattern.hasMatch(inputHash) ||
      !_hashPattern.hasMatch(proposalFingerprint) ||
      source == null) {
    return null;
  }

  final recommendationsRaw = map['recommendations'];
  if (recommendationsRaw is! List || recommendationsRaw.length > 5) {
    return null;
  }
  final recommendations = <DailyPlanRecommendation>[];
  final seenIds = <String>{};
  final seenPriorities = <int>{};
  for (final raw in recommendationsRaw) {
    if (raw is! Map) return null;
    final recommendation = Map<String, dynamic>.from(raw);
    if (!_hasOnlyKeys(recommendation, const {
      'taskId',
      'priority',
      'category',
      'reason',
      'suggestedMinutes',
    })) {
      return null;
    }
    final taskId = '${recommendation['taskId'] ?? ''}';
    final priority = recommendation['priority'];
    final reason = _safeText(recommendation['reason']);
    final suggestedMinutes = recommendation['suggestedMinutes'];
    if (!_taskIdPattern.hasMatch(taskId) ||
        effectiveAllowed != null && !effectiveAllowed.contains(taskId) ||
        !seenIds.add(taskId) ||
        priority is! int ||
        priority < 1 ||
        priority > 5 ||
        !seenPriorities.add(priority) ||
        recommendation['category'] != 'do_today' ||
        reason == null ||
        suggestedMinutes is! int ||
        suggestedMinutes < 5 ||
        suggestedMinutes > 180) {
      return null;
    }
    recommendations.add(
      DailyPlanRecommendation(
        taskId: taskId,
        priority: priority,
        reason: reason,
        suggestedMinutes: suggestedMinutes,
      ),
    );
  }
  recommendations.sort((a, b) => a.priority.compareTo(b.priority));

  final deferred = _taskIds(
    map['deferredTaskIds'],
    max: 20,
    allowedTaskIds: effectiveAllowed,
  );
  final warnings = _safeTexts(map['warnings'], max: 5);
  if (deferred == null || warnings == null) return null;
  if (deferred.any(seenIds.contains)) return null;
  if (plan != null && !_fitsPlanBudgets(plan, recommendations)) return null;

  final modelRaw = map['modelIdentifier'];
  final modelIdentifier =
      modelRaw is String && modelRaw.trim().isNotEmpty ? modelRaw.trim() : null;
  if (modelIdentifier != null && modelIdentifier.length > 80) return null;

  return DailyPlanProposal(
    schemaVersion: dailyPlanProposalSchemaVersion,
    summary: summary,
    recommendations: recommendations,
    deferredTaskIds: deferred,
    warnings: warnings,
    source: source,
    generatedAt: generatedAt,
    inputHash: inputHash,
    proposalFingerprint: proposalFingerprint,
    modelIdentifier: modelIdentifier,
  );
}

bool _fitsPlanBudgets(
  DailyPlan plan,
  List<DailyPlanRecommendation> recommendations,
) {
  final byId = {for (final item in plan.items) item.id: item};
  var resin = plan.currentResin;
  var minutes = plan.availableMinutes;
  for (final recommendation in recommendations) {
    final item = byId[recommendation.taskId];
    if (item == null || !item.availableToday) return false;
    if (item.estimatedMinutes != null &&
        recommendation.suggestedMinutes > item.estimatedMinutes!) {
      return false;
    }
    final cost = item.estimatedResinCost;
    if (item.requiresResin && resin == 0 ||
        resin != null && cost != null && cost > resin ||
        minutes != null && recommendation.suggestedMinutes > minutes) {
      return false;
    }
    if (resin != null && cost != null) resin -= cost;
    if (minutes != null) minutes -= recommendation.suggestedMinutes;
  }
  return true;
}

Map<String, dynamic> dailyPlanProposalToJson(DailyPlanProposal proposal) => {
  'schemaVersion': proposal.schemaVersion,
  'summary': proposal.summary,
  'recommendations': [
    for (final recommendation in proposal.recommendations)
      {
        'taskId': recommendation.taskId,
        'priority': recommendation.priority,
        'category': 'do_today',
        'reason': recommendation.reason,
        'suggestedMinutes': recommendation.suggestedMinutes,
      },
  ],
  'deferredTaskIds': proposal.deferredTaskIds,
  'warnings': proposal.warnings,
  'source': proposal.isAiGenerated ? 'deepseek' : 'deterministic_fallback',
  'generatedAt': proposal.generatedAt.toUtc().toIso8601String(),
  'inputHash': proposal.inputHash,
  'proposalFingerprint': proposal.proposalFingerprint,
  if (proposal.modelIdentifier != null)
    'modelIdentifier': proposal.modelIdentifier,
};

bool _hasOnlyKeys(Map<String, dynamic> map, Set<String> allowed) =>
    map.keys.every(allowed.contains);

String? _safeText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 120 ||
      _forbiddenFormat.hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

List<String>? _safeTexts(Object? value, {required int max}) {
  if (value is! List || value.length > max) return null;
  final out = <String>[];
  for (final entry in value) {
    final safe = _safeText(entry);
    if (safe == null) return null;
    out.add(safe);
  }
  return out;
}

List<String>? _taskIds(
  Object? value, {
  required int max,
  Set<String>? allowedTaskIds,
}) {
  if (value is! List || value.length > max) return null;
  final out = <String>[];
  final seen = <String>{};
  for (final entry in value) {
    if (entry is! String ||
        !_taskIdPattern.hasMatch(entry) ||
        allowedTaskIds != null && !allowedTaskIds.contains(entry) ||
        !seen.add(entry)) {
      return null;
    }
    out.add(entry);
  }
  return out;
}
