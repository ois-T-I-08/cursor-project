import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/hoyolab/models/daily_note.dart';
import 'notification_scheduler.dart';
import 'reminder_calculator.dart';
import 'reminder_models.dart';
import 'reminder_settings_store.dart';

class ReminderReconcileSnapshot {
  const ReminderReconcileSnapshot({
    required this.note,
    required this.fetchedAt,
  });

  final DailyNote note;
  final DateTime fetchedAt;
}

/// Serializes Fresh DailyNote reconciles with generation guards.
class NotificationScheduleCoordinator {
  NotificationScheduleCoordinator({
    required ReminderSettingsStore settings,
    required NotificationScheduler scheduler,
    HoyolabReminderCalculator calculator = const HoyolabReminderCalculator(),
    DateTime Function()? now,
  })  : _settings = settings,
        _scheduler = scheduler,
        _calculator = calculator,
        _now = now ?? DateTime.now;

  final ReminderSettingsStore _settings;
  final NotificationScheduler _scheduler;
  final HoyolabReminderCalculator _calculator;
  final DateTime Function() _now;

  Future<void>? _queue;
  int _sequence = 0;

  void reconcileUnawaited(ReminderReconcileSnapshot snapshot) {
    unawaited(reconcile(snapshot));
  }

  Future<void> reconcile(ReminderReconcileSnapshot snapshot) {
    Future<void> run() async {
      final seq = ++_sequence;
      try {
        await _reconcileBody(snapshot, seq);
      } catch (_) {
        debugPrint('notifications: reconcile failed');
      }
    }

    final previous = _queue;
    Future<void> next() async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await run();
    }

    final future = next();
    _queue = future;
    return future;
  }

  Future<void> cancelAllAndResetAccount() async {
    final previous = _queue;
    Future<void> next() async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      _sequence++;
      try {
        await _scheduler.cancelAllReminders();
      } catch (_) {
        debugPrint('notifications: cancelAllAndResetAccount cancel failed');
      }
      try {
        await _settings.resetReminderState();
        await _settings.bumpAccountGeneration();
      } catch (_) {
        debugPrint('notifications: cancelAllAndResetAccount reset failed');
      }
    }

    final future = next();
    _queue = future;
    return future;
  }

  Future<void> onPreferencesChangedCancelIfDisabled() async {
    final prefs = await _settings.readPreferences();
    final osOk = await _scheduler.areNotificationsEnabled();
    if (!prefs.resinEnabled || !osOk) {
      try {
        await _scheduler.cancel(ReminderKind.resin);
        await _settings.clearResinScheduleMeta(clearWasAtOrAbove: true);
      } catch (_) {
        debugPrint('notifications: disable resin cancel failed');
      }
    }
    if (!prefs.expeditionEnabled || !osOk) {
      try {
        await _scheduler.cancel(ReminderKind.expedition);
        await _settings.clearExpeditionScheduleMeta(clearAllComplete: true);
      } catch (_) {
        debugPrint('notifications: disable expedition cancel failed');
      }
    }
  }

  Future<void> _reconcileBody(
    ReminderReconcileSnapshot snapshot,
    int seq,
  ) async {
    final accountGen = await _settings.readAccountGeneration();
    final settingsGen = await _settings.readSettingsGeneration();
    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;

    final prefs = await _settings.readPreferences();
    final osOk = await _scheduler.areNotificationsEnabled();
    final prior = await _settings.readPriorState();
    final now = _now();

    final input = ReminderSnapshotInput(
      fetchedAt: snapshot.fetchedAt,
      accountGeneration: accountGen,
      currentResin: snapshot.note.currentResin,
      maxResin: snapshot.note.maxResin,
      hasMaxResinFromApi: snapshot.note.hasMaxResinFromApi,
      resinRecoveryTimeRaw: snapshot.note.resinRecoveryTime,
      expeditions: snapshot.note.expeditions
          .map(
            (e) => ExpeditionReminderInput(
              status: e.status,
              hasRemainingTimeFromApi: e.hasRemainingTimeFromApi,
              remainingSeconds: e.remainingSecondsFromApi,
            ),
          )
          .toList(growable: false),
    );

    final resinDecision = _calculator.calculateResin(
      snapshot: input,
      prior: prior,
      now: now,
    );
    final expeditionDecision = _calculator.calculateExpedition(
      snapshot: input,
      prior: prior,
      now: now,
    );

    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;

    await _applyDecision(
      decision: resinDecision,
      effectiveEnabled: prefs.resinEnabled && osOk,
      seq: seq,
      accountGen: accountGen,
      settingsGen: settingsGen,
    );
    await _applyDecision(
      decision: expeditionDecision,
      effectiveEnabled: prefs.expeditionEnabled && osOk,
      seq: seq,
      accountGen: accountGen,
      settingsGen: settingsGen,
    );
  }

  Future<void> _applyDecision({
    required ReminderDecision decision,
    required bool effectiveEnabled,
    required int seq,
    required String accountGen,
    required String settingsGen,
  }) async {
    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;

    switch (decision.type) {
      case ReminderDecisionType.keepExisting:
        return;
      case ReminderDecisionType.skipInvalid:
      case ReminderDecisionType.cancel:
        await _cancelCategory(
          decision.kind,
          reasonCode: decision.reasonCode,
          seq: seq,
          accountGen: accountGen,
          settingsGen: settingsGen,
        );
        return;
      case ReminderDecisionType.scheduleAt:
      case ReminderDecisionType.notifyImmediately:
        if (!effectiveEnabled) {
          await _cancelCategory(
            decision.kind,
            reasonCode: 'disabled',
            seq: seq,
            accountGen: accountGen,
            settingsGen: settingsGen,
          );
          return;
        }
        break;
    }

    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;

    if (decision.type == ReminderDecisionType.notifyImmediately) {
      try {
        await _scheduler.cancel(decision.kind);
      } catch (_) {}
      if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
      try {
        await _scheduler.show(
          kind: decision.kind,
          title: _title(decision.kind),
          body: _body(decision.kind),
          payload: _payload(decision.kind),
        );
      } catch (_) {
        debugPrint('notifications: immediate show failed');
        return;
      }
      if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
      final fp = decision.scheduleFingerprint ?? '';
      if (decision.kind == ReminderKind.resin) {
        await _settings.markResinImmediateNotified(fingerprint: fp);
      } else {
        await _settings.markExpeditionImmediateNotified(fingerprint: fp);
      }
      return;
    }

    if (decision.type == ReminderDecisionType.scheduleAt) {
      final notifyAt = decision.notifyAt!;
      try {
        await _scheduler.cancel(decision.kind);
      } catch (_) {}
      if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
      try {
        await _scheduler.schedule(
          kind: decision.kind,
          notifyAt: notifyAt,
          title: _title(decision.kind),
          body: _body(decision.kind),
          payload: _payload(decision.kind),
        );
      } catch (_) {
        debugPrint('notifications: schedule apply failed');
        return;
      }
      if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
      final fp = decision.scheduleFingerprint ?? '';
      if (decision.kind == ReminderKind.resin) {
        await _settings.markResinSchedule(
          scheduledAt: notifyAt,
          fingerprint: fp,
        );
      } else {
        await _settings.markExpeditionSchedule(
          scheduledAt: notifyAt,
          fingerprint: fp,
        );
      }
    }
  }

  Future<void> _cancelCategory(
    ReminderKind kind, {
    String? reasonCode,
    required int seq,
    required String accountGen,
    required String settingsGen,
  }) async {
    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
    try {
      await _scheduler.cancel(kind);
    } catch (_) {
      debugPrint('notifications: category cancel failed');
      return;
    }
    if (!await _stillCurrent(seq, accountGen, settingsGen)) return;
    final keepState = reasonCode == 'already_at_or_above' ||
        reasonCode == 'already_all_complete';
    if (kind == ReminderKind.resin) {
      await _settings.clearResinScheduleMeta(clearWasAtOrAbove: !keepState);
    } else {
      await _settings.clearExpeditionScheduleMeta(clearAllComplete: !keepState);
    }
  }

  Future<bool> _stillCurrent(
    int seq,
    String accountGen,
    String settingsGen,
  ) async {
    if (seq != _sequence) return false;
    final a = await _settings.readAccountGeneration();
    final s = await _settings.readSettingsGeneration();
    return a == accountGen && s == settingsGen;
  }

  static String _title(ReminderKind kind) => switch (kind) {
        ReminderKind.resin => ReminderNotificationIds.resinTitle,
        ReminderKind.expedition => ReminderNotificationIds.expeditionTitle,
      };

  static String _body(ReminderKind kind) => switch (kind) {
        ReminderKind.resin => ReminderNotificationIds.resinBody,
        ReminderKind.expedition => ReminderNotificationIds.expeditionBody,
      };

  static String _payload(ReminderKind kind) => switch (kind) {
        ReminderKind.resin => ReminderNotificationIds.resinPayload,
        ReminderKind.expedition => ReminderNotificationIds.expeditionPayload,
      };
}
