import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/amber/amber_master_parsers.dart';
import 'package:genshin_builder_mobile/data/daily_materials/composite_daily_material_schedule_source.dart';
import 'package:genshin_builder_mobile/data/daily_materials/daily_material_schedule_repository.dart';
import 'package:genshin_builder_mobile/data/models/sync_status.dart';
import 'package:genshin_builder_mobile/data/sync/master_content_probe.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';

void main() {
  group('countSyncableCharactersFromAmberItems', () {
    test('matches parse filter (skips female traveler)', () {
      final items = {
        'a': {
          'id': 10000042,
          'name': '刻晴',
          'element': 'Electric',
        },
        'skip': {
          'id': '10000007-anemo',
          'name': '旅人',
          'element': 'Wind',
        },
        't': {
          'id': '10000005-anemo',
          'name': '旅人',
          'element': 'Wind',
        },
        'bad': {
          'id': 1,
          'name': 'x',
          // no element
        },
      };
      expect(countSyncableCharactersFromAmberItems(items), 2);
      expect(parseCharactersFromAmberItems(items).length, 2);
    });
  });

  group('SyncStatus.shouldAutoSyncOnLaunch', () {
    test('true when unsynced or missing upgrades (compat wide gate)', () {
      expect(
        const SyncStatus(
          characters: 0,
          weapons: 0,
          materials: 0,
          characterUpgrades: 0,
          weaponUpgrades: 0,
          levelExpSegments: 0,
        ).shouldAutoSyncOnLaunch,
        isTrue,
      );
      expect(
        const SyncStatus(
          characters: 10,
          weapons: 5,
          materials: 100,
          characterUpgrades: 8,
          weaponUpgrades: 5,
          levelExpSegments: 32,
        ).shouldAutoSyncOnLaunch,
        isTrue,
      );
      expect(
        const SyncStatus(
          characters: 10,
          weapons: 5,
          materials: 100,
          characterUpgrades: 10,
          weaponUpgrades: 5,
          levelExpSegments: 32,
        ).shouldAutoSyncOnLaunch,
        isFalse,
      );
    });

    test('requiresBlockingBootstrap is narrower than shouldAutoSyncOnLaunch',
        () {
      const missingUpgrades = SyncStatus(
        characters: 10,
        weapons: 5,
        materials: 100,
        characterUpgrades: 8,
        weaponUpgrades: 5,
        levelExpSegments: 32,
      );
      expect(missingUpgrades.shouldAutoSyncOnLaunch, isTrue);
      expect(missingUpgrades.requiresBlockingBootstrap, isFalse);
    });
  });

  group('MasterContentProbeResult', () {
    test('reasonSummary joins reasons', () {
      const r = MasterContentProbeResult(
        shouldSync: true,
        reasons: ['新キャラ 2 件', '未取得のキャラ突破 1 件'],
      );
      expect(r.reasonSummary, contains('新キャラ'));
      expect(r.reasonSummary, contains('突破'));
    });
  });

  group('CompositeDailyMaterialScheduleSource', () {
    test('prefers remote when version is higher', () async {
      final local = _FakeScheduleSource(
        DailyMaterialSchedule(
          version: 1,
          talentSeries: const [],
          weaponSeries: const [],
        ),
      );
      final remote = _FakeScheduleSource(
        DailyMaterialSchedule(
          version: 2,
          talentSeries: [
            DailyMaterialSeries.fromJson(
              {
                'id': 'freedom',
                'name': '自由',
                'materialIds': ['104301'],
                'weekdays': [1, 4],
              },
              DailyMaterialKind.talentBook,
            ),
          ],
          weaponSeries: const [],
        ),
      );
      final composite = CompositeDailyMaterialScheduleSource(
        localSource: local,
        remoteSource: remote,
      );
      final schedule = await composite.load();
      expect(schedule.version, 2);
      expect(schedule.talentSeries, hasLength(1));
    });

    test('falls back to local when remote fails', () async {
      final local = _FakeScheduleSource(
        const DailyMaterialSchedule(
          version: 3,
          talentSeries: [],
          weaponSeries: [],
        ),
      );
      final composite = CompositeDailyMaterialScheduleSource(
        localSource: local,
        remoteSource: _FailingScheduleSource(),
      );
      final schedule = await composite.load();
      expect(schedule.version, 3);
    });

    test('keeps local when remote version is older', () async {
      final local = _FakeScheduleSource(
        const DailyMaterialSchedule(
          version: 5,
          talentSeries: [],
          weaponSeries: [],
        ),
      );
      final remote = _FakeScheduleSource(
        const DailyMaterialSchedule(
          version: 2,
          talentSeries: [],
          weaponSeries: [],
        ),
      );
      final composite = CompositeDailyMaterialScheduleSource(
        localSource: local,
        remoteSource: remote,
      );
      expect((await composite.load()).version, 5);
    });
  });
}

class _FakeScheduleSource implements DailyMaterialScheduleSource {
  _FakeScheduleSource(this.schedule);
  final DailyMaterialSchedule schedule;

  @override
  Future<DailyMaterialSchedule> load() async => schedule;
}

class _FailingScheduleSource implements DailyMaterialScheduleSource {
  @override
  Future<DailyMaterialSchedule> load() async {
    throw Exception('network');
  }
}
