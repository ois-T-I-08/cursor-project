import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_home_disk_cache.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/daily_note.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';

class _MemorySettingsStore implements HoyolabSettingsStore {
  final _values = <String, String>{};

  @override
  Future<String?> getSetting(String key) async => _values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  group('HoyolabHomeDiskCache', () {
    late HoyolabHomeDiskCache cache;

    setUp(() {
      cache = HoyolabHomeDiskCache(_MemorySettingsStore());
    });

    test('roundtrips daily note', () async {
      const note = DailyNote(
        currentResin: 80,
        maxResin: 160,
        resinRecoveryTime: '1200',
        finishedTaskNum: 4,
        totalTaskNum: 4,
        currentHomeCoin: 500,
        maxHomeCoin: 2400,
        expeditions: [
          HoyolabExpedition(status: 'Finished', remainingTime: '0'),
        ],
      );

      await cache.saveDailyNote('123456', note);
      final loaded = await cache.readDailyNote('123456');

      expect(loaded, isNotNull);
      expect(loaded!.data.currentResin, 80);
      expect(loaded.data.finishedExpeditions, 1);
    });

    test('roundtrips adventure status', () async {
      const status = AdventureStatus(
        spiralAbyss: SpiralAbyssStatus(
          maxFloor: '12-3',
          totalStars: 36,
          isUnlocked: true,
          scheduleId: 1,
        ),
        imaginariumTheater: ImaginariumTheaterStatus(
          isUnlocked: true,
          difficultyId: 3,
          maxRoundId: 8,
          medalNum: 12,
          hasData: true,
        ),
      );

      await cache.saveAdventure('123456', status);
      final loaded = await cache.readAdventure('123456');

      expect(loaded, isNotNull);
      expect(loaded!.data.spiralAbyss?.maxFloor, '12-3');
      expect(loaded.data.imaginariumTheater?.difficultyLabel, 'ハード');
    });

    test('clearForUid removes cached entries', () async {
      const note = DailyNote(
        currentResin: 1,
        maxResin: 160,
        resinRecoveryTime: '0',
        finishedTaskNum: 0,
        totalTaskNum: 4,
        currentHomeCoin: 0,
        maxHomeCoin: 2400,
        expeditions: [],
      );

      await cache.saveDailyNote('999', note);
      await cache.clearForUid('999');

      expect(await cache.readDailyNote('999'), isNull);
    });
  });
}
