import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/models/sync_status.dart';
import 'package:genshin_builder_mobile/data/sync/background_master_repair.dart';
import 'package:genshin_builder_mobile/data/sync/master_content_probe.dart';
import 'package:genshin_builder_mobile/data/sync/master_sync_service.dart';

SyncStatus _status({
  int characters = 10,
  int weapons = 5,
  int materials = 100,
  int characterUpgrades = 10,
  int weaponUpgrades = 5,
  int levelExpSegments = 32,
}) {
  return SyncStatus(
    characters: characters,
    weapons: weapons,
    materials: materials,
    characterUpgrades: characterUpgrades,
    weaponUpgrades: weaponUpgrades,
    levelExpSegments: levelExpSegments,
  );
}

void main() {
  group('SyncStatus bootstrap gates', () {
    test('requiresBlockingBootstrap only when characters == 0', () {
      expect(_status(characters: 0).requiresBlockingBootstrap, isTrue);
      expect(
        _status(
          characters: 10,
          characterUpgrades: 0,
        ).requiresBlockingBootstrap,
        isFalse,
      );
      expect(
        _status(
          characters: 10,
          characterUpgrades: 8,
        ).requiresBlockingBootstrap,
        isFalse,
      );
      expect(
        _status(characters: 10, weapons: 0).requiresBlockingBootstrap,
        isFalse,
      );
      expect(
        _status(characters: 10, materials: 0).requiresBlockingBootstrap,
        isFalse,
      );
    });

    test('needsInitialUpgradeSync and hasMissingUpgrades do not block', () {
      final initial = _status(characterUpgrades: 0);
      expect(initial.needsInitialUpgradeSync, isTrue);
      expect(initial.requiresBlockingBootstrap, isFalse);
      expect(initial.needsBackgroundRepair, isTrue);

      final missing = _status(characterUpgrades: 8);
      expect(missing.hasMissingUpgrades, isTrue);
      expect(missing.requiresBlockingBootstrap, isFalse);
      expect(missing.needsBackgroundRepair, isTrue);
    });

    test('needsBackgroundRepair covers weapons/materials zero', () {
      expect(
        _status(weapons: 0).needsBackgroundRepair,
        isTrue,
      );
      expect(
        _status(materials: 0).needsBackgroundRepair,
        isTrue,
      );
      expect(
        _status(levelExpSegments: 0).needsBackgroundRepair,
        isTrue,
      );
    });
  });

  group('BackgroundMasterRepair', () {
    test('ensureStartedAfterHome is idempotent after completion', () async {
      var syncCount = 0;
      var probeCount = 0;
      var iconCount = 0;

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(),
        runProbe: () async {
          probeCount++;
          return const MasterContentProbeResult(
            shouldSync: false,
            reasons: [],
          );
        },
        runMasterSync: () async {
          syncCount++;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async {
          iconCount++;
          return 0;
        },
        backfillWeights: () async {},
      );

      await repair.ensureStartedAfterHome();
      await repair.ensureStartedAfterHome();
      await repair.ensureStartedAfterHome();

      expect(probeCount, 1);
      expect(syncCount, 0);
      expect(iconCount, 1);
      expect(repair.startedAfterHome, isTrue);
    });

    test('concurrent ensureStartedAfterHome joins same Future', () async {
      var syncCount = 0;
      final gate = Completer<void>();

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(characterUpgrades: 0),
        runProbe: () async => const MasterContentProbeResult(
          shouldSync: false,
          reasons: [],
        ),
        runMasterSync: () async {
          syncCount++;
          await gate.future;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async => 0,
        backfillWeights: () async {},
      );

      final a = repair.ensureStartedAfterHome();
      final b = repair.ensureStartedAfterHome();
      expect(identical(a, b), isTrue);
      gate.complete();
      await Future.wait([a, b]);
      expect(syncCount, 1);
    });

    test('bootstrap mark skips probe and master sync', () async {
      var syncCount = 0;
      var probeCount = 0;
      var iconCount = 0;

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(characterUpgrades: 0),
        runProbe: () async {
          probeCount++;
          return const MasterContentProbeResult(
            shouldSync: true,
            reasons: ['new'],
          );
        },
        runMasterSync: () async {
          syncCount++;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async {
          iconCount++;
          return 1;
        },
        backfillWeights: () async {},
      );

      repair.markMasterSyncCompletedDuringBootstrap();
      await repair.ensureStartedAfterHome();

      expect(probeCount, 0);
      expect(syncCount, 0);
      expect(iconCount, 1);
    });

    test('manual sync during busy returns busy without joining as success',
        () async {
      final gate = Completer<void>();
      var manualRuns = 0;

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(characterUpgrades: 0),
        runProbe: () async => const MasterContentProbeResult(
          shouldSync: false,
          reasons: [],
        ),
        runMasterSync: () async {
          await gate.future;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async => 0,
        backfillWeights: () async {},
      );

      final bg = repair.ensureStartedAfterHome();
      expect(repair.isBusy, isTrue);

      final start = await repair.runManualExclusive(() async {
        manualRuns++;
      });
      expect(start, ManualSyncStart.busy);
      expect(manualRuns, 0);

      gate.complete();
      await bg;

      final start2 = await repair.runManualExclusive(() async {
        manualRuns++;
      });
      expect(start2, ManualSyncStart.completed);
      expect(manualRuns, 1);
    });

    test('probe timeout late result does not start master sync', () async {
      var syncCount = 0;
      final lateProbe = Completer<MasterContentProbeResult>();

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(),
        runProbe: () => lateProbe.future,
        runMasterSync: () async {
          syncCount++;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async => 0,
        backfillWeights: () async {},
        probeTimeout: const Duration(milliseconds: 20),
      );

      await repair.ensureStartedAfterHome();
      expect(syncCount, 0);

      // 遅延完了（timeout 後）— shouldSync でも採用しない
      lateProbe.complete(
        const MasterContentProbeResult(
          shouldSync: true,
          reasons: ['late'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(syncCount, 0);
    });

    test('needsBackgroundRepair triggers sync without waiting probe shouldSync',
        () async {
      var syncCount = 0;
      var probeCount = 0;

      final repair = BackgroundMasterRepair(
        loadSyncStatus: () async => _status(characterUpgrades: 8),
        runProbe: () async {
          probeCount++;
          return const MasterContentProbeResult(
            shouldSync: false,
            reasons: [],
          );
        },
        runMasterSync: () async {
          syncCount++;
          return SyncResult(provider: 'test');
        },
        preloadIcons: () async => 0,
        backfillWeights: () async {},
      );

      await repair.ensureStartedAfterHome();
      expect(syncCount, 1);
      // repair が必要なときは probe をスキップして直接 sync
      expect(probeCount, 0);
    });
  });
}
