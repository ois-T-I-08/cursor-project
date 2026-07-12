import '../../data/hoyolab/hoyolab_home_disk_cache.dart';
import 'reminder_models.dart';

/// AppSettings KV keys for P1-8B (no Cookie / UID / API bodies).
abstract final class ReminderSettingsKeys {
  static const resinEnabled = 'p1_8b_pref_resin_enabled';
  static const expeditionEnabled = 'p1_8b_pref_expedition_enabled';
  static const resinWasAtOrAbove190 = 'p1_8b_resin_was_at_or_above_190';
  static const resinScheduledAt = 'p1_8b_resin_scheduled_at';
  static const resinScheduleFingerprint = 'p1_8b_resin_schedule_fp';
  static const expeditionAllComplete = 'p1_8b_expedition_all_complete';
  static const expeditionScheduledAt = 'p1_8b_expedition_scheduled_at';
  static const expeditionScheduleFingerprint = 'p1_8b_expedition_schedule_fp';
  static const accountGeneration = 'p1_8b_account_generation';
  static const settingsGeneration = 'p1_8b_settings_generation';
}

class ReminderUserPreferences {
  const ReminderUserPreferences({
    required this.resinEnabled,
    required this.expeditionEnabled,
  });

  final bool resinEnabled;
  final bool expeditionEnabled;

  bool get anyEnabled => resinEnabled || expeditionEnabled;
}

class ReminderSettingsStore {
  ReminderSettingsStore(this._store);

  final HoyolabSettingsStore _store;

  Future<ReminderUserPreferences> readPreferences() async {
    return ReminderUserPreferences(
      resinEnabled: await _readBool(ReminderSettingsKeys.resinEnabled),
      expeditionEnabled:
          await _readBool(ReminderSettingsKeys.expeditionEnabled),
    );
  }

  Future<void> setResinEnabled(bool enabled) async {
    await _store.setSetting(
      ReminderSettingsKeys.resinEnabled,
      enabled.toString(),
    );
    await bumpSettingsGeneration();
  }

  Future<void> setExpeditionEnabled(bool enabled) async {
    await _store.setSetting(
      ReminderSettingsKeys.expeditionEnabled,
      enabled.toString(),
    );
    await bumpSettingsGeneration();
  }

  Future<ReminderPriorState> readPriorState() async {
    return ReminderPriorState(
      resinWasAtOrAbove190:
          await _readBool(ReminderSettingsKeys.resinWasAtOrAbove190),
      expeditionAllComplete:
          await _readBool(ReminderSettingsKeys.expeditionAllComplete),
      resinScheduledAt: await _readDate(ReminderSettingsKeys.resinScheduledAt),
      resinScheduleFingerprint:
          await _store.getSetting(ReminderSettingsKeys.resinScheduleFingerprint),
      expeditionScheduledAt:
          await _readDate(ReminderSettingsKeys.expeditionScheduledAt),
      expeditionScheduleFingerprint: await _store
          .getSetting(ReminderSettingsKeys.expeditionScheduleFingerprint),
    );
  }

  Future<String> readAccountGeneration() async {
    final raw = await _store.getSetting(ReminderSettingsKeys.accountGeneration);
    if (raw == null || raw.isEmpty) return '0';
    return raw;
  }

  Future<String> readSettingsGeneration() async {
    final raw = await _store.getSetting(ReminderSettingsKeys.settingsGeneration);
    if (raw == null || raw.isEmpty) return '0';
    return raw;
  }

  Future<String> bumpAccountGeneration() async {
    final next = (int.tryParse(await readAccountGeneration()) ?? 0) + 1;
    final value = next.toString();
    await _store.setSetting(ReminderSettingsKeys.accountGeneration, value);
    return value;
  }

  Future<String> bumpSettingsGeneration() async {
    final next = (int.tryParse(await readSettingsGeneration()) ?? 0) + 1;
    final value = next.toString();
    await _store.setSetting(ReminderSettingsKeys.settingsGeneration, value);
    return value;
  }

  Future<void> markResinSchedule({
    required DateTime scheduledAt,
    required String fingerprint,
  }) async {
    await _store.setSetting(
      ReminderSettingsKeys.resinScheduledAt,
      scheduledAt.toUtc().toIso8601String(),
    );
    await _store.setSetting(
      ReminderSettingsKeys.resinScheduleFingerprint,
      fingerprint,
    );
    await _store.setSetting(
      ReminderSettingsKeys.resinWasAtOrAbove190,
      'false',
    );
  }

  Future<void> markResinImmediateNotified({required String fingerprint}) async {
    await _store.setSetting(
      ReminderSettingsKeys.resinWasAtOrAbove190,
      'true',
    );
    await _store.setSetting(ReminderSettingsKeys.resinScheduledAt, '');
    await _store.setSetting(
      ReminderSettingsKeys.resinScheduleFingerprint,
      fingerprint,
    );
  }

  Future<void> clearResinScheduleMeta({required bool clearWasAtOrAbove}) async {
    await _store.setSetting(ReminderSettingsKeys.resinScheduledAt, '');
    await _store.setSetting(ReminderSettingsKeys.resinScheduleFingerprint, '');
    if (clearWasAtOrAbove) {
      await _store.setSetting(
        ReminderSettingsKeys.resinWasAtOrAbove190,
        'false',
      );
    }
  }

  Future<void> markExpeditionSchedule({
    required DateTime scheduledAt,
    required String fingerprint,
  }) async {
    await _store.setSetting(
      ReminderSettingsKeys.expeditionScheduledAt,
      scheduledAt.toUtc().toIso8601String(),
    );
    await _store.setSetting(
      ReminderSettingsKeys.expeditionScheduleFingerprint,
      fingerprint,
    );
    await _store.setSetting(
      ReminderSettingsKeys.expeditionAllComplete,
      'false',
    );
  }

  Future<void> markExpeditionImmediateNotified({
    required String fingerprint,
  }) async {
    await _store.setSetting(
      ReminderSettingsKeys.expeditionAllComplete,
      'true',
    );
    await _store.setSetting(ReminderSettingsKeys.expeditionScheduledAt, '');
    await _store.setSetting(
      ReminderSettingsKeys.expeditionScheduleFingerprint,
      fingerprint,
    );
  }

  Future<void> clearExpeditionScheduleMeta({
    required bool clearAllComplete,
  }) async {
    await _store.setSetting(ReminderSettingsKeys.expeditionScheduledAt, '');
    await _store.setSetting(
      ReminderSettingsKeys.expeditionScheduleFingerprint,
      '',
    );
    if (clearAllComplete) {
      await _store.setSetting(
        ReminderSettingsKeys.expeditionAllComplete,
        'false',
      );
    }
  }

  Future<void> resetReminderState() async {
    await clearResinScheduleMeta(clearWasAtOrAbove: true);
    await clearExpeditionScheduleMeta(clearAllComplete: true);
  }

  Future<bool> _readBool(String key) async {
    final raw = await _store.getSetting(key);
    return raw == 'true';
  }

  Future<DateTime?> _readDate(String key) async {
    final raw = await _store.getSetting(key);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
