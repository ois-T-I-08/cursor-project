import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/reminder_calculator.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/reminder_models.dart';

void main() {
  const calc = HoyolabReminderCalculator();
  final now = DateTime.utc(2026, 7, 12, 12, 0, 0);
  final fetchedAt = now.subtract(const Duration(seconds: 10));

  ReminderSnapshotInput base({
    int currentResin = 100,
    int maxResin = 200,
    bool hasMaxResinFromApi = true,
    String recovery = '8000',
    List<ExpeditionReminderInput>? expeditions,
  }) {
    return ReminderSnapshotInput(
      fetchedAt: fetchedAt,
      accountGeneration: '1',
      currentResin: currentResin,
      maxResin: maxResin,
      hasMaxResinFromApi: hasMaxResinFromApi,
      resinRecoveryTimeRaw: recovery,
      expeditions: expeditions ?? const [],
    );
  }

  ReminderPriorState prior({
    bool wasAtOrAbove = false,
    bool expeditionDone = false,
    String? resinFp,
    DateTime? resinAt,
  }) {
    return ReminderPriorState(
      resinWasAtOrAbove190: wasAtOrAbove,
      expeditionAllComplete: expeditionDone,
      resinScheduleFingerprint: resinFp,
      resinScheduledAt: resinAt,
    );
  }

  group('resin', () {
    test('current 0 schedules with ceil math', () {
      // needed=190, remainingToMax=200, recovery=8000
      // seconds = ceil(8000*190/200) = 7600
      final d = calc.calculateResin(
        snapshot: base(currentResin: 0, maxResin: 200, recovery: '8000'),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
      expect(
        d.notifyAt,
        fetchedAt.add(const Duration(seconds: 7600)),
      );
    });

    test('current 189 schedules 1 resin worth', () {
      // needed=1, remaining=11, recovery=880 → ceil(880/11)=80
      final d = calc.calculateResin(
        snapshot: base(currentResin: 189, maxResin: 200, recovery: '880'),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
      expect(d.notifyAt, fetchedAt.add(const Duration(seconds: 80)));
    });

    test('exactly 190 notifies immediately once', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 190),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.notifyImmediately);
    });

    test('above 190 notifies immediately once', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 195),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.notifyImmediately);
    });

    test('maxResin 190 eligible', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 100, maxResin: 190, recovery: '7200'),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
    });

    test('maxResin below 190 cancels', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 100, maxResin: 160, recovery: '4800'),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.cancel);
      expect(d.reasonCode, 'max_resin_below_190');
    });

    test('max_resin missing cancels', () {
      final d = calc.calculateResin(
        snapshot: base(hasMaxResinFromApi: false, maxResin: 160),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.cancel);
      expect(d.reasonCode, 'max_resin_missing');
    });

    test('recovery 0 / missing / negative cancel', () {
      for (final r in ['0', '', '-1', 'x']) {
        final d = calc.calculateResin(
          snapshot: base(recovery: r),
          prior: prior(),
          now: now,
        );
        expect(d.type, ReminderDecisionType.cancel, reason: r);
      }
    });

    test('ceil does not notify early via float', () {
      // recovery=100, needed=2, remaining=3 → ceil(200/3)=67 not 66
      final d = calc.calculateResin(
        snapshot: base(currentResin: 188, maxResin: 191, recovery: '100'),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
      expect(d.notifyAt, fetchedAt.add(const Duration(seconds: 67)));
    });

    test('past notifyAt becomes immediate', () {
      final lateFetched = now.subtract(const Duration(hours: 2));
      final d = calc.calculateResin(
        snapshot: ReminderSnapshotInput(
          fetchedAt: lateFetched,
          accountGeneration: '1',
          currentResin: 189,
          maxResin: 200,
          hasMaxResinFromApi: true,
          resinRecoveryTimeRaw: '80',
          expeditions: const [],
        ),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.notifyImmediately);
    });

    test('>=190 continuing cancels without re-notify flag clear reason', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 190),
        prior: prior(wasAtOrAbove: true),
        now: now,
      );
      expect(d.type, ReminderDecisionType.cancel);
      expect(d.reasonCode, 'already_at_or_above');
    });

    test('drop below 190 schedules again', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 100, recovery: '8000'),
        prior: prior(wasAtOrAbove: true),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
    });

    test('secondsTo190 never exceeds recovery', () {
      final d = calc.calculateResin(
        snapshot: base(currentResin: 0, maxResin: 200, recovery: '100'),
        prior: prior(),
        now: now,
      );
      // ceil(100*190/200)=95 <= 100
      expect(d.type, ReminderDecisionType.scheduleAt);
      expect(
        d.notifyAt!.difference(fetchedAt).inSeconds,
        lessThanOrEqualTo(100),
      );
    });
  });

  group('expedition', () {
    List<ExpeditionReminderInput> five(List<int> secs, {String status = 'Ongoing'}) {
      return secs
          .map(
            (s) => ExpeditionReminderInput(
              status: status,
              hasRemainingTimeFromApi: true,
              remainingSeconds: s,
            ),
          )
          .toList();
    }

    test('5 valid schedules at max remaining', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([10, 20, 30, 5, 1])),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
      expect(d.notifyAt, fetchedAt.add(const Duration(seconds: 30)));
    });

    test('4 items cancel', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([1, 2, 3, 4]).take(4).toList()),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.cancel);
      expect(d.reasonCode, 'count_not_five');
    });

    test('6 items cancel', () {
      final d = calc.calculateExpedition(
        snapshot: base(
          expeditions: [
            ...five([1, 2, 3, 4, 5]),
            const ExpeditionReminderInput(
              status: 'Ongoing',
              hasRemainingTimeFromApi: true,
              remainingSeconds: 6,
            ),
          ],
        ),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.cancel);
    });

    test('remaining missing cancel', () {
      final list = five([1, 2, 3, 4, 5]);
      list[2] = const ExpeditionReminderInput(
        status: 'Ongoing',
        hasRemainingTimeFromApi: false,
        remainingSeconds: null,
      );
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: list),
        prior: prior(),
        now: now,
      );
      expect(d.reasonCode, 'remaining_missing');
    });

    test('negative remaining cancel', () {
      final list = five([1, 2, 3, 4, 5]);
      list[1] = const ExpeditionReminderInput(
        status: 'Ongoing',
        hasRemainingTimeFromApi: true,
        remainingSeconds: -1,
      );
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: list),
        prior: prior(),
        now: now,
      );
      expect(d.reasonCode, 'remaining_negative');
    });

    test('all zero notifies once', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([0, 0, 0, 0, 0])),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.notifyImmediately);
    });

    test('Ongoing+0 allowed as complete', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([0, 0, 0, 0, 0], status: 'Ongoing')),
        prior: prior(),
        now: now,
      );
      expect(d.type, ReminderDecisionType.notifyImmediately);
    });

    test('Finished+positive invalid', () {
      final list = five([0, 0, 0, 0, 10], status: 'Finished');
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: list),
        prior: prior(),
        now: now,
      );
      expect(d.reasonCode, 'finished_positive_remaining');
    });

    test('complete continuing keeps state via cancel reason', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([0, 0, 0, 0, 0])),
        prior: prior(expeditionDone: true),
        now: now,
      );
      expect(d.reasonCode, 'already_all_complete');
    });

    test('redeploy clears complete path by scheduling', () {
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: five([100, 50, 30, 20, 10])),
        prior: prior(expeditionDone: true),
        now: now,
      );
      expect(d.type, ReminderDecisionType.scheduleAt);
    });

    test('unknown status cancel', () {
      final list = five([1, 2, 3, 4, 5]);
      list[0] = const ExpeditionReminderInput(
        status: 'Unknown',
        hasRemainingTimeFromApi: true,
        remainingSeconds: 1,
      );
      final d = calc.calculateExpedition(
        snapshot: base(expeditions: list),
        prior: prior(),
        now: now,
      );
      expect(d.reasonCode, 'status_unknown');
    });
  });
}
