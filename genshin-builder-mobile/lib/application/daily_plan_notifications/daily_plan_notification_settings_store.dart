import '../../data/hoyolab/hoyolab_home_disk_cache.dart';

/// AppSettings KV keys for P1-8C (no Cookie / UID / API bodies).
abstract final class DailyPlanNotificationSettingsKeys {
  static const incompleteEnabled = 'p1_8c_pref_incomplete_enabled';
  static const lastUniqueWorkName = 'p1_8c_last_unique_work_name';
}

class DailyPlanNotificationSettingsStore {
  DailyPlanNotificationSettingsStore(this._store);

  final HoyolabSettingsStore _store;

  Future<bool> isIncompleteEnabled() async {
    final raw =
        await _store.getSetting(DailyPlanNotificationSettingsKeys.incompleteEnabled);
    return raw == 'true';
  }

  Future<void> setIncompleteEnabled(bool enabled) async {
    await _store.setSetting(
      DailyPlanNotificationSettingsKeys.incompleteEnabled,
      enabled.toString(),
    );
  }

  Future<String?> readLastUniqueWorkName() =>
      _store.getSetting(DailyPlanNotificationSettingsKeys.lastUniqueWorkName);

  Future<void> writeLastUniqueWorkName(String name) => _store.setSetting(
        DailyPlanNotificationSettingsKeys.lastUniqueWorkName,
        name,
      );

  Future<void> clearLastUniqueWorkName() => _store.setSetting(
        DailyPlanNotificationSettingsKeys.lastUniqueWorkName,
        '',
      );
}
