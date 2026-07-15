/// Pure incomplete-count logic for daily plan vs completion keys.
class DailyPlanCompletionEvaluator {
  const DailyPlanCompletionEvaluator();

  /// Incomplete = plan keys that are not in [completedItemKeys].
  ///
  /// Keys present only in completions (vanished from plan) are ignored.
  int countIncomplete({
    required Iterable<String> planItemKeys,
    required Set<String> completedItemKeys,
  }) {
    var count = 0;
    for (final key in planItemKeys) {
      if (!completedItemKeys.contains(key)) {
        count++;
      }
    }
    return count;
  }

  /// Whether a notification should be considered (non-empty plan + incomplete > 0).
  bool shouldNotifyCandidate({
    required Iterable<String> planItemKeys,
    required Set<String> completedItemKeys,
  }) {
    final keys = planItemKeys.toList(growable: false);
    if (keys.isEmpty) return false;
    return countIncomplete(
          planItemKeys: keys,
          completedItemKeys: completedItemKeys,
        ) >
        0;
  }
}
