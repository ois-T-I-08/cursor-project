import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_home_disk_cache.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/daily_note.dart';

import '../../application/hoyolab_reminders/in_memory_settings_store.dart';

void main() {
  group('DailyNote presence', () {
    test('API max_resin present sets hasMaxResinFromApi', () {
      final note = DailyNote.fromJsonSource({
        'current_resin': 10,
        'max_resin': 200,
        'resin_recovery_time': '1',
        'expeditions': [],
      }, fromApi: true);
      expect(note.hasMaxResinFromApi, isTrue);
      expect(note.maxResin, 200);
    });

    test('API max_resin missing falls back 160 without presence', () {
      final note = DailyNote.fromJsonSource({
        'current_resin': 10,
        'resin_recovery_time': '1',
        'expeditions': [],
      }, fromApi: true);
      expect(note.hasMaxResinFromApi, isFalse);
      expect(note.maxResin, 160);
    });

    test('old cache without presence flags does not schedule presence', () {
      final note = DailyNote.fromJsonSource({
        'current_resin': 10,
        'max_resin': 200,
        'resin_recovery_time': '1',
        'expeditions': [
          {'status': 'Ongoing', 'remaining_time': '10'},
        ],
      }, fromApi: false);
      expect(note.hasMaxResinFromApi, isFalse);
      expect(note.expeditions.single.hasRemainingTimeFromApi, isFalse);
      expect(note.expeditions.single.remainingSecondsFromApi, isNull);
    });

    test('remaining_time 0 with presence is distinct from missing', () {
      final withZero = HoyolabExpedition.fromJsonSource({
        'status': 'Ongoing',
        'remaining_time': '0',
      }, fromApi: true);
      expect(withZero.hasRemainingTimeFromApi, isTrue);
      expect(withZero.remainingSecondsFromApi, 0);

      final missing = HoyolabExpedition.fromJsonSource({
        'status': 'Ongoing',
      }, fromApi: true);
      expect(missing.hasRemainingTimeFromApi, isFalse);
      expect(missing.remainingSecondsFromApi, isNull);
    });
  });

  group('disk cache fetchedAt', () {
    test('save and read keep provided fetchedAt', () async {
      final store = InMemoryHoyolabSettingsStore();
      final cache = HoyolabHomeDiskCache(store);
      final fetchedAt = DateTime.utc(2026, 7, 12, 10, 0, 0);
      final note = DailyNote.fromJson({
        'current_resin': 1,
        'max_resin': 200,
        'resin_recovery_time': '1',
        'expeditions': [],
      });
      await cache.saveDailyNote('uid1', note, fetchedAt: fetchedAt);
      final entry = await cache.readDailyNote('uid1');
      expect(entry, isNotNull);
      expect(entry!.fetchedAt.toUtc(), fetchedAt);
      // Fresh save includes presence flags in payload.
      expect(entry.data.hasMaxResinFromApi, isTrue);
    });

    test('legacy cache without presence flags stays safe-false', () async {
      final store = InMemoryHoyolabSettingsStore();
      final cache = HoyolabHomeDiskCache(store);
      await store.setSetting(
        HoyolabHomeDiskCache.dailyNoteKey('uid1'),
        '{"fetched_at":"2026-07-12T10:00:00.000Z","payload":{"current_resin":1,"max_resin":200,"resin_recovery_time":"1","expeditions":[{"status":"Ongoing","remaining_time":"10"}]}}',
      );
      final entry = await cache.readDailyNote('uid1');
      expect(entry, isNotNull);
      expect(entry!.data.hasMaxResinFromApi, isFalse);
      expect(entry.data.expeditions.single.hasRemainingTimeFromApi, isFalse);
    });
  });
}
