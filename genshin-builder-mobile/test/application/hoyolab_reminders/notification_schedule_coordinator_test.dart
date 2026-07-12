import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/notification_schedule_coordinator.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/notification_scheduler.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/reminder_models.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/reminder_settings_store.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/daily_note.dart';

import 'in_memory_settings_store.dart';

void main() {
  late InMemoryHoyolabSettingsStore kv;
  late ReminderSettingsStore settings;
  late RecordingNotificationScheduler scheduler;
  late NotificationScheduleCoordinator coordinator;
  var now = DateTime.utc(2026, 7, 12, 12, 0, 0);

  setUp(() async {
    kv = InMemoryHoyolabSettingsStore();
    settings = ReminderSettingsStore(kv);
    scheduler = RecordingNotificationScheduler();
    now = DateTime.utc(2026, 7, 12, 12, 0, 0);
    coordinator = NotificationScheduleCoordinator(
      settings: settings,
      scheduler: scheduler,
      now: () => now,
    );
    await settings.setResinEnabled(true);
    await settings.setExpeditionEnabled(true);
    scheduler.ops.clear();
  });

  DailyNote note({
    int resin = 100,
    int maxResin = 200,
    bool hasMax = true,
    String recovery = '8000',
    List<HoyolabExpedition>? expeditions,
  }) {
    return DailyNote(
      currentResin: resin,
      maxResin: maxResin,
      hasMaxResinFromApi: hasMax,
      resinRecoveryTime: recovery,
      finishedTaskNum: 0,
      totalTaskNum: 4,
      currentHomeCoin: 0,
      maxHomeCoin: 2400,
      expeditions: expeditions ??
          List.generate(
            5,
            (i) => HoyolabExpedition(
              status: 'Ongoing',
              remainingTime: '${100 + i}',
              hasRemainingTimeFromApi: true,
            ),
          ),
    );
  }

  test('schedules then stores metadata only after plugin success', () async {
    final fetchedAt = now.subtract(const Duration(seconds: 5));
    await coordinator.reconcile(
      ReminderReconcileSnapshot(note: note(), fetchedAt: fetchedAt),
    );
    expect(scheduler.ops.any((o) => o.startsWith('schedule:resin')), isTrue);
    final prior = await settings.readPriorState();
    expect(prior.resinScheduledAt, isNotNull);
    expect(prior.resinScheduleFingerprint, isNotNull);
  });

  test('plugin schedule failure does not store success meta', () async {
    scheduler.failSchedule = true;
    final fetchedAt = now.subtract(const Duration(seconds: 5));
    await coordinator.reconcile(
      ReminderReconcileSnapshot(note: note(), fetchedAt: fetchedAt),
    );
    final prior = await settings.readPriorState();
    expect(prior.resinScheduledAt, isNull);
  });

  test('API success invalid cancels old category', () async {
    await settings.markResinSchedule(
      scheduledAt: now.add(const Duration(hours: 1)),
      fingerprint: 'old',
    );
    scheduler.ops.clear();
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(hasMax: false, maxResin: 160),
        fetchedAt: now,
      ),
    );
    expect(scheduler.ops, contains('cancel:resin'));
    final prior = await settings.readPriorState();
    expect(prior.resinScheduledAt, isNull);
  });

  test('notification OFF does not schedule', () async {
    await settings.setResinEnabled(false);
    await settings.setExpeditionEnabled(false);
    scheduler.ops.clear();
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(),
        fetchedAt: now.subtract(const Duration(seconds: 1)),
      ),
    );
    expect(scheduler.ops.any((o) => o.startsWith('schedule:')), isFalse);
    expect(scheduler.ops.any((o) => o.startsWith('show:')), isFalse);
  });

  test('permission denied does not schedule; preference kept', () async {
    scheduler.permissionGranted = false;
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(),
        fetchedAt: now.subtract(const Duration(seconds: 1)),
      ),
    );
    expect(scheduler.ops.any((o) => o.startsWith('schedule:')), isFalse);
    final prefs = await settings.readPreferences();
    expect(prefs.resinEnabled, isTrue);
  });

  test('settings generation change aborts in-flight before schedule', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final delaying = _GateOnCancelScheduler(
      inner: scheduler,
      entered: entered,
      gate: gate,
    );
    final local = NotificationScheduleCoordinator(
      settings: settings,
      scheduler: delaying,
      now: () => now,
    );
    final fetchedAt = now.subtract(const Duration(seconds: 1));
    final future = local.reconcile(
      ReminderReconcileSnapshot(note: note(), fetchedAt: fetchedAt),
    );
    await entered.future;
    await settings.setResinEnabled(false);
    await settings.setExpeditionEnabled(false);
    gate.complete();
    await future;
    expect(scheduler.ops.any((o) => o.startsWith('schedule:')), isFalse);
  });

  test('older snapshot loses to newer via sequence', () async {
    final first = coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(resin: 0),
        fetchedAt: now.subtract(const Duration(seconds: 2)),
      ),
    );
    final second = coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(resin: 190),
        fetchedAt: now.subtract(const Duration(seconds: 1)),
      ),
    );
    await Future.wait([first, second]);
    expect(scheduler.ops.where((o) => o == 'show:resin'), isNotEmpty);
  });

  test('disconnect cancel/reset bumps account generation', () async {
    await settings.markResinImmediateNotified(fingerprint: 'x');
    final before = await settings.readAccountGeneration();
    await coordinator.cancelAllAndResetAccount();
    expect(scheduler.ops, contains('cancelAll'));
    final after = await settings.readAccountGeneration();
    expect(int.parse(after), greaterThan(int.parse(before)));
    final prior = await settings.readPriorState();
    expect(prior.resinWasAtOrAbove190, isFalse);
  });

  test('account switch invalidates in-flight schedule', () async {
    final fetchedAt = now.subtract(const Duration(seconds: 1));
    final reconcile = coordinator.reconcile(
      ReminderReconcileSnapshot(note: note(), fetchedAt: fetchedAt),
    );
    await coordinator.cancelAllAndResetAccount();
    await reconcile;
    final prior = await settings.readPriorState();
    expect(prior.resinScheduledAt, isNull);
  });

  test('immediate show failure does not mark notified', () async {
    scheduler.failShow = true;
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(resin: 190),
        fetchedAt: now,
      ),
    );
    final prior = await settings.readPriorState();
    expect(prior.resinWasAtOrAbove190, isFalse);
  });

  test('KV does not store cookie/uid/api body keys', () async {
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(resin: 190),
        fetchedAt: now,
      ),
    );
    for (final key in kv.values.keys) {
      expect(key.toLowerCase().contains('cookie'), isFalse);
      expect(key.toLowerCase().contains('ltoken'), isFalse);
      expect(key.contains('uid'), isFalse);
    }
    for (final value in kv.values.values) {
      expect(value.contains('ltoken'), isFalse);
      expect(value.contains('cookie'), isFalse);
    }
  });

  test('count not five cancels expedition category', () async {
    await settings.markExpeditionSchedule(
      scheduledAt: now.add(const Duration(hours: 1)),
      fingerprint: 'old-e',
    );
    scheduler.ops.clear();
    await coordinator.reconcile(
      ReminderReconcileSnapshot(
        note: note(
          expeditions: [
            const HoyolabExpedition(
              status: 'Ongoing',
              remainingTime: '10',
              hasRemainingTimeFromApi: true,
            ),
          ],
        ),
        fetchedAt: now,
      ),
    );
    expect(scheduler.ops, contains('cancel:expedition'));
  });
}

class _GateOnCancelScheduler implements NotificationScheduler {
  _GateOnCancelScheduler({
    required this.inner,
    required this.entered,
    required this.gate,
  });

  final RecordingNotificationScheduler inner;
  final Completer<void> entered;
  final Completer<void> gate;
  bool _gated = false;

  @override
  Future<bool> areNotificationsEnabled() => inner.areNotificationsEnabled();

  @override
  Future<bool> requestPermission() => inner.requestPermission();

  @override
  Future<void> show({
    required ReminderKind kind,
    required String title,
    required String body,
    required String payload,
  }) =>
      inner.show(kind: kind, title: title, body: body, payload: payload);

  @override
  Future<void> schedule({
    required ReminderKind kind,
    required DateTime notifyAt,
    required String title,
    required String body,
    required String payload,
  }) =>
      inner.schedule(
        kind: kind,
        notifyAt: notifyAt,
        title: title,
        body: body,
        payload: payload,
      );

  @override
  Future<void> cancel(ReminderKind kind) async {
    if (!_gated) {
      _gated = true;
      if (!entered.isCompleted) entered.complete();
      await gate.future;
    }
    await inner.cancel(kind);
  }

  @override
  Future<void> cancelAllReminders() => inner.cancelAllReminders();
}
