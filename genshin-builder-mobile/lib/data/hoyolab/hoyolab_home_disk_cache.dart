import 'dart:convert';

import '../db/app_database.dart';
import 'hoyolab_constants.dart';
import 'models/daily_note.dart';
import 'models/game_record.dart';

abstract class HoyolabSettingsStore {
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
}

class AppDatabaseSettingsStore implements HoyolabSettingsStore {
  AppDatabaseSettingsStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> getSetting(String key) => _db.getSetting(key);

  @override
  Future<void> setSetting(String key, String value) =>
      _db.setSetting(key, value);
}

class HoyolabCachedEntry<T> {
  const HoyolabCachedEntry({
    required this.data,
    required this.fetchedAt,
  });

  final T data;
  final DateTime fetchedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(fetchedAt) < ttl;
}

/// ホーム画面用 HoYoLAB データのディスクキャッシュ（Stale-While-Revalidate 用）
class HoyolabHomeDiskCache {
  HoyolabHomeDiskCache(HoyolabSettingsStore store) : _store = store;

  final HoyolabSettingsStore _store;

  static String dailyNoteKey(String uid) => 'hoyolab_cache_daily_note_$uid';
  static String adventureKey(String uid) => 'hoyolab_cache_adventure_$uid';

  Future<HoyolabCachedEntry<DailyNote>?> readDailyNote(String uid) =>
      _read(
        key: dailyNoteKey(uid),
        parse: (json) => DailyNote.fromJsonSource(json, fromApi: false),
      );

  Future<void> saveDailyNote(
    String uid,
    DailyNote note, {
    DateTime? fetchedAt,
  }) =>
      _write(
        key: dailyNoteKey(uid),
        payload: note.toJson(),
        fetchedAt: fetchedAt,
      );

  Future<HoyolabCachedEntry<AdventureStatus>?> readAdventure(String uid) =>
      _read(
        key: adventureKey(uid),
        parse: AdventureStatus.fromCacheJson,
      );

  Future<void> saveAdventure(String uid, AdventureStatus status) => _write(
        key: adventureKey(uid),
        payload: status.toJson(),
      );

  Future<void> clearForUid(String uid) async {
    await _store.setSetting(dailyNoteKey(uid), '');
    await _store.setSetting(adventureKey(uid), '');
  }

  Future<HoyolabCachedEntry<T>?> _read<T>({
    required String key,
    required T Function(Map<String, dynamic> json) parse,
  }) async {
    final raw = await _store.getSetting(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAtRaw = decoded['fetched_at'] as String?;
      final payload = decoded['payload'] as Map<String, dynamic>?;
      if (fetchedAtRaw == null || payload == null) return null;

      final fetchedAt = DateTime.tryParse(fetchedAtRaw);
      if (fetchedAt == null) return null;

      return HoyolabCachedEntry(
        data: parse(payload),
        fetchedAt: fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _write({
    required String key,
    required Map<String, dynamic> payload,
    DateTime? fetchedAt,
  }) async {
    final encoded = jsonEncode({
      'fetched_at': (fetchedAt ?? DateTime.now()).toIso8601String(),
      'payload': payload,
    });
    await _store.setSetting(key, encoded);
  }
}

/// キャッシュ TTL（テスト・参照用）
const hoyolabDailyNoteDiskTtl = HoyolabConstants.dailyNoteCacheTtl;
const hoyolabAdventureDiskTtl = HoyolabConstants.adventureStatusCacheTtl;
