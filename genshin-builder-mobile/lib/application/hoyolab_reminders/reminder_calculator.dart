import 'reminder_models.dart';

/// Pure reminder decisions (no plugin / I/O).
class HoyolabReminderCalculator {
  const HoyolabReminderCalculator();

  ReminderDecision calculateResin({
    required ReminderSnapshotInput snapshot,
    required ReminderPriorState prior,
    required DateTime now,
  }) {
    final fetchedAt = snapshot.fetchedAt;
    if (fetchedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return ReminderDecision.skipInvalid(
        ReminderKind.resin,
        'fetched_at_invalid',
      );
    }

    if (snapshot.currentResin < 0) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'negative_resin',
      );
    }

    if (snapshot.currentResin >= 190) {
      if (prior.resinWasAtOrAbove190) {
        // Keep notified state; drop any stale future schedule.
        return ReminderDecision.cancel(
          ReminderKind.resin,
          reasonCode: 'already_at_or_above',
        );
      }
      return ReminderDecision.notifyImmediately(
        kind: ReminderKind.resin,
        scheduleFingerprint: _immediateResinFp(snapshot.accountGeneration),
      );
    }

    // current < 190
    if (!snapshot.hasMaxResinFromApi) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'max_resin_missing',
      );
    }
    if (snapshot.maxResin < 190) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'max_resin_below_190',
      );
    }
    if (snapshot.currentResin >= snapshot.maxResin) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'resin_at_max_below_190',
      );
    }

    final recovery = int.tryParse(snapshot.resinRecoveryTimeRaw);
    if (recovery == null || recovery <= 0) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'recovery_invalid',
      );
    }

    final remainingToMax = snapshot.maxResin - snapshot.currentResin;
    if (remainingToMax <= 0) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'remaining_to_max_invalid',
      );
    }

    final needed = 190 - snapshot.currentResin;
    // ceil(recovery * needed / remainingToMax) via integer math
    final secondsTo190 =
        (recovery * needed + remainingToMax - 1) ~/ remainingToMax;
    if (secondsTo190 <= 0 || secondsTo190 > recovery) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'seconds_to_190_invalid',
      );
    }

    final notifyAt = fetchedAt.add(Duration(seconds: secondsTo190));
    if (notifyAt.difference(fetchedAt) > ReminderNotificationIds.maxScheduleHorizon) {
      return ReminderDecision.cancel(
        ReminderKind.resin,
        reasonCode: 'horizon_exceeded',
      );
    }

    if (!notifyAt.isAfter(now)) {
      return ReminderDecision.notifyImmediately(
        kind: ReminderKind.resin,
        scheduleFingerprint: _immediateResinFp(snapshot.accountGeneration),
      );
    }

    final fp = _scheduleResinFp(
      accountGeneration: snapshot.accountGeneration,
      currentResin: snapshot.currentResin,
      maxResin: snapshot.maxResin,
      recovery: recovery,
      notifyAt: notifyAt,
    );

    if (prior.resinScheduleFingerprint == fp &&
        prior.resinScheduledAt != null &&
        _sameEpochMinute(prior.resinScheduledAt!, notifyAt)) {
      return ReminderDecision.keepExisting(ReminderKind.resin);
    }

    return ReminderDecision.scheduleAt(
      kind: ReminderKind.resin,
      notifyAt: notifyAt,
      scheduleFingerprint: fp,
    );
  }

  ReminderDecision calculateExpedition({
    required ReminderSnapshotInput snapshot,
    required ReminderPriorState prior,
    required DateTime now,
  }) {
    final fetchedAt = snapshot.fetchedAt;
    if (fetchedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return ReminderDecision.skipInvalid(
        ReminderKind.expedition,
        'fetched_at_invalid',
      );
    }

    final list = snapshot.expeditions;
    if (list.length != 5) {
      return ReminderDecision.cancel(
        ReminderKind.expedition,
        reasonCode: 'count_not_five',
      );
    }

    final seconds = <int>[];
    for (final e in list) {
      if (!e.hasRemainingTimeFromApi || e.remainingSeconds == null) {
        return ReminderDecision.cancel(
          ReminderKind.expedition,
          reasonCode: 'remaining_missing',
        );
      }
      final sec = e.remainingSeconds!;
      if (sec < 0) {
        return ReminderDecision.cancel(
          ReminderKind.expedition,
          reasonCode: 'remaining_negative',
        );
      }

      final status = e.status.toLowerCase();
      if (status != 'finished' && status != 'ongoing') {
        return ReminderDecision.cancel(
          ReminderKind.expedition,
          reasonCode: 'status_unknown',
        );
      }
      // Finished + positive remaining = inconsistent
      if (status == 'finished' && sec > 0) {
        return ReminderDecision.cancel(
          ReminderKind.expedition,
          reasonCode: 'finished_positive_remaining',
        );
      }
      // Ongoing + 0 is allowed (just completed)
      seconds.add(sec);
    }

    final maxRemaining = seconds.reduce((a, b) => a > b ? a : b);
    final allComplete = maxRemaining == 0;

    if (allComplete) {
      if (prior.expeditionAllComplete) {
        return ReminderDecision.cancel(
          ReminderKind.expedition,
          reasonCode: 'already_all_complete',
        );
      }
      return ReminderDecision.notifyImmediately(
        kind: ReminderKind.expedition,
        scheduleFingerprint: _immediateExpeditionFp(snapshot.accountGeneration),
      );
    }

    final notifyAt = fetchedAt.add(Duration(seconds: maxRemaining));
    if (notifyAt.difference(fetchedAt) > ReminderNotificationIds.maxScheduleHorizon) {
      return ReminderDecision.cancel(
        ReminderKind.expedition,
        reasonCode: 'horizon_exceeded',
      );
    }

    if (!notifyAt.isAfter(now)) {
      return ReminderDecision.notifyImmediately(
        kind: ReminderKind.expedition,
        scheduleFingerprint: _immediateExpeditionFp(snapshot.accountGeneration),
      );
    }

    final fp = _scheduleExpeditionFp(
      accountGeneration: snapshot.accountGeneration,
      seconds: seconds,
      notifyAt: notifyAt,
    );

    if (prior.expeditionScheduleFingerprint == fp &&
        prior.expeditionScheduledAt != null &&
        _sameEpochMinute(prior.expeditionScheduledAt!, notifyAt)) {
      return ReminderDecision.keepExisting(ReminderKind.expedition);
    }

    return ReminderDecision.scheduleAt(
      kind: ReminderKind.expedition,
      notifyAt: notifyAt,
      scheduleFingerprint: fp,
    );
  }

  static String _immediateResinFp(String gen) => '$gen|resin_ge_190';

  static String _immediateExpeditionFp(String gen) => '$gen|expedition_all_done';

  static String _scheduleResinFp({
    required String accountGeneration,
    required int currentResin,
    required int maxResin,
    required int recovery,
    required DateTime notifyAt,
  }) =>
      '$accountGeneration|r|$currentResin|$maxResin|$recovery|${_epochMinute(notifyAt)}';

  static String _scheduleExpeditionFp({
    required String accountGeneration,
    required List<int> seconds,
    required DateTime notifyAt,
  }) =>
      '$accountGeneration|e|${seconds.join(',')}|${_epochMinute(notifyAt)}';

  static int _epochMinute(DateTime dt) =>
      dt.toUtc().millisecondsSinceEpoch ~/ 60000;

  static bool _sameEpochMinute(DateTime a, DateTime b) =>
      _epochMinute(a) == _epochMinute(b);
}
