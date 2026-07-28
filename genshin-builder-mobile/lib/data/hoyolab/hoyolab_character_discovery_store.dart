import 'dart:convert';

import 'hoyolab_home_disk_cache.dart';
import 'models/game_record.dart';

/// HoYoLAB に取得日が無い場合、アプリ内で新規所持を記録して取得推定日とする
class HoyolabCharacterDiscoveryStore {
  HoyolabCharacterDiscoveryStore(this._store);

  final HoyolabSettingsStore _store;

  static String snapshotKey(String uid) => 'hoyolab_owned_snapshot_$uid';

  static String discoveredMapKey(String uid) =>
      'hoyolab_char_discovered_map_$uid';

  Future<Map<String, HoyolabOwnedCharacter>> enrichOwnedCharacters({
    required String uid,
    required Map<String, HoyolabOwnedCharacter> characters,
  }) async {
    if (characters.isEmpty) return characters;

    final currentIds = characters.keys.toList(growable: false)..sort();
    final previousIds = await _readSnapshot(uid);
    final discoveredMap = await _readDiscoveredMap(uid);
    final now = DateTime.now();

    if (previousIds.isNotEmpty) {
      final previousSet = previousIds.toSet();
      for (final id in currentIds) {
        if (previousSet.contains(id) || discoveredMap.containsKey(id)) continue;
        discoveredMap[id] = now;
      }
    }

    await _writeSnapshot(uid, currentIds);
    if (discoveredMap.isNotEmpty) {
      await _writeDiscoveredMap(uid, discoveredMap);
    }

    final enriched = <String, HoyolabOwnedCharacter>{};
    for (final entry in characters.entries) {
      var character = entry.value;
      if (character.obtainedAt == null) {
        final discovered = discoveredMap[entry.key];
        if (discovered != null) {
          character = character.copyWith(obtainedAt: discovered);
        }
      }
      enriched[entry.key] = character;
    }
    return enriched;
  }

  Future<void> clearForUid(String uid) async {
    await _store.setSetting(snapshotKey(uid), '');
    await _store.setSetting(discoveredMapKey(uid), '');
  }

  Future<List<String>> _readSnapshot(String uid) async {
    final raw = await _store.getSetting(snapshotKey(uid));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => '$e').toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeSnapshot(String uid, List<String> ids) async {
    await _store.setSetting(snapshotKey(uid), jsonEncode(ids));
  }

  Future<Map<String, DateTime>> _readDiscoveredMap(String uid) async {
    final raw = await _store.getSetting(discoveredMapKey(uid));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, DateTime>{};
      for (final entry in decoded.entries) {
        final parsed = DateTime.tryParse('${entry.value}');
        if (parsed != null) {
          map[entry.key] = parsed;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeDiscoveredMap(
    String uid,
    Map<String, DateTime> discoveredMap,
  ) async {
    final encoded = <String, String>{};
    for (final entry in discoveredMap.entries) {
      encoded[entry.key] = entry.value.toIso8601String();
    }
    await _store.setSetting(discoveredMapKey(uid), jsonEncode(encoded));
  }
}
