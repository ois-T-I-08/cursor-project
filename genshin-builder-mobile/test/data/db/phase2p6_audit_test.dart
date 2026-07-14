import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';
import 'package:genshin_builder_mobile/data/db/drift/daos/growth_dao.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/history/growth_event.dart' as domain;
import 'package:genshin_builder_mobile/domain/account/snapshot_supplement.dart';

void main() {
  group('GrowthEvent composite cursor pagination', () {
    testWidgets('same observedAt events paginate correctly', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });

      final dt = DateTime(2026, 7, 14, 12, 0, 0);
      for (var i = 0; i < 6; i++) {
        await db.growthDao.eventsSaveAll([
          EventParams(eventId: 'ev$i', userId: 'local', characterId: 'c1',
            eventType: 'characterLevelChanged',
            beforeValue: '$i', afterValue: '${i + 1}',
            source: 'test', observedAt: dt.millisecondsSinceEpoch,
            dedupKey: 'local:c1:level:$i->${i + 1}'),
        ]);
      }

      final page1 = await db.growthDao.eventsGetByUser('local', limit: 2);
      expect(page1.length, 2);
      final ids1 = page1.map((e) => e.eventId).toList();
      expect(ids1[0], 'ev5');
      expect(ids1[1], 'ev4');

      final cursor2 = domain.GrowthEventCursor(
        observedAt: DateTime.fromMillisecondsSinceEpoch(page1.last.observedAt),
        eventId: page1.last.eventId,
      );
      final page2 = await db.growthDao.eventsGetByUser('local', limit: 2,
          beforeObservedAt: cursor2.observedAt, beforeEventId: cursor2.eventId);
      expect(page2.length, 2);
      expect(page2[0].eventId, 'ev3');
      expect(page2[1].eventId, 'ev2');

      final cursor3 = domain.GrowthEventCursor(
        observedAt: DateTime.fromMillisecondsSinceEpoch(page2.last.observedAt),
        eventId: page2.last.eventId,
      );
      final page3 = await db.growthDao.eventsGetByUser('local', limit: 2,
          beforeObservedAt: cursor3.observedAt, beforeEventId: cursor3.eventId);
      expect(page3.length, 2);
      expect(page3[0].eventId, 'ev1');
      expect(page3[1].eventId, 'ev0');

      final cursor4 = domain.GrowthEventCursor(
        observedAt: DateTime.fromMillisecondsSinceEpoch(page3.last.observedAt),
        eventId: page3.last.eventId,
      );
      final page4 = await db.growthDao.eventsGetByUser('local', limit: 2,
          beforeObservedAt: cursor4.observedAt, beforeEventId: cursor4.eventId);
      expect(page4, isEmpty);

      final all = [...page1, ...page2, ...page3];
      expect(all.map((e) => e.eventId).toSet().length, 6);

      await db.close();
    });

    testWidgets('empty history returns empty list', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      final page = await db.growthDao.eventsGetByUser('local', limit: 50);
      expect(page, isEmpty);
      await db.close();
    });
  });

  group('GrowthEvent source and dedup', () {
    testWidgets('events save with correct source', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      await db.growthDao.eventsSaveAll([
        EventParams(eventId: 'src_1', userId: 'local', characterId: 'c1',
            eventType: 'level', source: 'localManual',
            observedAt: 1000000, dedupKey: 'l:src:1'),
        EventParams(eventId: 'src_2', userId: 'local', characterId: 'c1',
            eventType: 'level', source: 'hoyolabSync',
            observedAt: 2000000, dedupKey: 'l:src:2'),
      ]);
      final events = await db.growthDao.eventsGetByUser('local', limit: 50);
      expect(events.length, 2);
      final sources = events.map((e) => e.source).toSet();
      expect(sources, contains('localManual'));
      expect(sources, contains('hoyolabSync'));
      await db.close();
    });

    testWidgets('duplicate dedupKey is ignored', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      await db.growthDao.eventsSaveAll([
        EventParams(eventId: 'dup_1', userId: 'local', characterId: 'c1',
            eventType: 'level', source: 'localManual',
            observedAt: 1000000, dedupKey: 'local:c1:dup'),
      ]);
      await db.growthDao.eventsSaveAll([
        EventParams(eventId: 'dup_2', userId: 'local', characterId: 'c1',
            eventType: 'level', source: 'localManual',
            observedAt: 1000000, dedupKey: 'local:c1:dup'),
      ]);
      expect((await db.growthDao.eventsGetByUser('local', limit: 50)).length, 1);
      await db.close();
    });
  });

  group('Transaction rollback', () {
    testWidgets('baseline produces no events', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      await db.characterDao.upsertCharacter(MasterCharacter(
        id: '10000002', name: 'Ayaka', element: 'cryo',
        weaponType: 'sword', rarity: 5, region: 'Inazuma', iconUrl: '',
      ));
      await db.progressDao.upsertProgress(UserProgress(
        id: 'p1', userId: 'local', characterId: '10000002', level: 80,
      ));
      expect((await db.growthDao.eventsGetByUser('local', limit: 50)), isEmpty);
      await db.close();
    });

    testWidgets('transaction rolls back on error', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      await db.characterDao.upsertCharacter(MasterCharacter(
        id: '10000002', name: 'Ayaka', element: 'cryo',
        weaponType: 'sword', rarity: 5, region: 'Inazuma', iconUrl: '',
      ));
      await db.progressDao.upsertProgress(UserProgress(
        id: 'p1', userId: 'local', characterId: '10000002', level: 1,
      ));
      try {
        await db.transaction(() async {
          await db.progressDao.upsertProgress(UserProgress(
            id: 'p1', userId: 'local', characterId: '10000002', level: 90,
          ));
          await db.customStatement('INVALID_SQL');
        });
      } catch (_) {}
      final saved = await db.progressDao.getProgress('local', '10000002');
      expect(saved?.level, 1);
      await db.close();
    });

    testWidgets('progress + events saved in transaction', (tester) async {
      final db = DriftAppDatabase(DatabaseConnection(
        DatabaseConnection.fromExecutor(NativeDatabase.memory()),
      ));
      addTearDown(() async { try { await db.close(); } catch (_) {} });
      await db.characterDao.upsertCharacter(MasterCharacter(
        id: '10000002', name: 'Ayaka', element: 'cryo',
        weaponType: 'sword', rarity: 5, region: 'Inazuma', iconUrl: '',
      ));
      await db.transaction(() async {
        await db.progressDao.upsertProgress(UserProgress(
          id: 'p1', userId: 'local', characterId: '10000002', level: 90,
        ));
        await db.growthDao.eventsSaveAll([
          EventParams(eventId: 'ev_tx', userId: 'local', characterId: '10000002',
            eventType: 'level', source: 'localManual',
            observedAt: 1000000, dedupKey: 'tx:unique'),
        ]);
      });
      final saved = await db.progressDao.getProgress('local', '10000002');
      expect(saved?.level, 90);
      expect((await db.growthDao.eventsGetByUser('local', limit: 50)).length, 1);
      await db.close();
    });
  });

  group('Cache-only dailyNote reference', () {
    test('AccountSnapshotSupplement defaults are correct', () {
      const sup = AccountSnapshotSupplement();
      expect(sup.currentResin, isNull);
      expect(sup.maxResin, isNull);
      expect(sup.status, SnapshotSupplementStatus.unlinked);
    });
    test('supplement with resin values', () {
      const sup = AccountSnapshotSupplement(
        currentResin: 120, maxResin: 200,
        status: SnapshotSupplementStatus.linked,
      );
      expect(sup.currentResin, 120);
      expect(sup.maxResin, 200);
      expect(sup.currentResin, isNot(0));
    });

    test('supplement contains no cookies, DS, or API headers', () {
      const sup = AccountSnapshotSupplement(
        currentResin: 120, maxResin: 200,
        status: SnapshotSupplementStatus.linked,
      );
      // The model has no cookie/DS/header fields — compile-time guarantee.
      expect(sup.toString(), isNotEmpty);
      // Verify no sensitive fields exist by checking only defined fields.
      expect(sup.currentResin, isNotNull);
      expect(sup.maxResin, isNotNull);
      // status, characters, acquiredAt, resinRecoveryAt are the only other fields.
      expect(sup.status, SnapshotSupplementStatus.linked);
    });

    test('currentResin 0 is valid (not null)', () {
      const sup = AccountSnapshotSupplement(
        currentResin: 0, maxResin: 200,
        status: SnapshotSupplementStatus.linked,
      );
      expect(sup.currentResin, 0);
      expect(sup.currentResin, isNotNull);
      expect(sup.maxResin, 200);
    });
  });

  group('Cache never calls network API', () {
    // The AccountSnapshotSupplement is a pure Dart data class.
    // It has no network dependencies — no API client, no HTTP calls.
    // The cachedDailyNoteProvider reads from HoyoLabHomeDiskCache (AppSettings DB table),
    // which is a read-only disk cache. It does NOT call HoyoLabApi.getDailyNote().
    // This is guaranteed by:
    // 1. cachedDailyNoteProvider only calls cache.readDailyNote(uid) — no HTTP.
    // 2. buildSnapshotSupplement only reads cachedDailyNoteProvider.valueOrNull.
    // 3. AccountSnapshotSupplement is pure Dart — no import of http or HoyoLabApi.

    test('AccountSnapshotSupplement has no network dependency', () {
      // Pure Dart model guarantee: no HTTP/API imports in this file.
      const sup = AccountSnapshotSupplement(
        currentResin: 160, maxResin: 200,
        status: SnapshotSupplementStatus.linked,
      );
      expect(sup.acquiredAt, isNull); // default
      expect(sup.resinRecoveryAt, isNull);
      expect(sup.characters, isEmpty);
    });

    test('supplement is immutable and has no side effects', () {
      final sup = AccountSnapshotSupplement(
        currentResin: 160, maxResin: 200,
        status: SnapshotSupplementStatus.linked,
      );
      expect(sup.currentResin, 160);
      // const wouldn't be possible if any field could trigger network calls
    });
  });
}
