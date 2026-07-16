import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';
import 'package:genshin_builder_mobile/data/db/drift/daos/growth_dao.dart';

void main() {
  group('DB migration v6 → v7', () {
    testWidgets('v7 database creates growth tables on fresh install',
        (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      // Verify new v7 tables exist
      final goalsTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='growth_goals'",
      ).get();
      expect(goalsTable, isNotEmpty);

      final invTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='user_material_inventory'",
      ).get();
      expect(invTable, isNotEmpty);

      final teamsTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='saved_teams'",
      ).get();
      expect(teamsTable, isNotEmpty);

      final eventsTable = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='growth_events'",
      ).get();
      expect(eventsTable, isNotEmpty);

      await db.close();
    });

    testWidgets('existing v6 tables still exist alongside v7 tables',
        (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      final chars = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='characters'",
      ).get();
      expect(chars, isNotEmpty);

      final progress = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='user_progress'",
      ).get();
      expect(progress, isNotEmpty);

      await db.close();
    });

    testWidgets('growth goal CRUD works', (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.growthDao.goalUpsert(GrowthGoalsCompanion(
        id: const Value('g1'),
        userId: const Value('local'),
        characterId: const Value('10000002'),
        targetLevel: const Value(90),
        status: const Value('active'),
        createdAt: Value(now),
      ));

      final goals = await db.growthDao.goalsGetAll('local');
      expect(goals.length, 1);
      expect(goals.first.id, 'g1');

      // Update
      await db.growthDao.goalUpsert(const GrowthGoalsCompanion(
        id: Value('g1'),
        userId: Value('local'),
        characterId: Value('10000002'),
        targetLevel: Value(80),
        status: Value('active'),
      ));
      final updated = await db.growthDao.goalGetById('g1');
      expect(updated!.targetLevel, 80);

      // Delete
      await db.growthDao.goalDelete('g1');
      final afterDelete = await db.growthDao.goalsGetAll('local');
      expect(afterDelete, isEmpty);

      await db.close();
    });

    testWidgets('material inventory CRUD works', (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      await db.growthDao.inventorySetQuantity('local', 'mat_a', 10);
      await db.growthDao.inventorySetQuantity('local', 'mat_b', 0);

      final inv = await db.growthDao.inventoryGet('local');
      expect(inv.length, 2);

      // 0 quantity should be distinguishable from missing
      final matB = inv.firstWhere((r) => r.materialId == 'mat_b');
      expect(matB.quantity, 0);

      await db.growthDao.inventoryDelete('local', 'mat_a');
      final afterDelete = await db.growthDao.inventoryGet('local');
      expect(afterDelete.length, 1);

      await db.close();
    });

    testWidgets('growth event dedup works via unique index', (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      final dt = DateTime.now().millisecondsSinceEpoch;
      await db.growthDao.eventsSaveAll([
        EventParams(
          eventId: 'e1',
          userId: 'local',
          characterId: '10000002',
          eventType: 'characterLevelChanged',
          observedAt: dt,
          dedupKey: 'local:10000002:characterLevelChanged:1->2',
        ),
      ]);

      // Insert duplicate — should be ignored silently
      await db.growthDao.eventsSaveAll([
        EventParams(
          eventId: 'e2',
          userId: 'local',
          characterId: '10000002',
          eventType: 'characterLevelChanged',
          observedAt: dt,
          dedupKey: 'local:10000002:characterLevelChanged:1->2',
        ),
      ]);

      final events = await db.growthDao.eventsGetByUser('local');
      expect(events.length, 1, reason: 'Duplicate event should be ignored');

      await db.close();
    });

    testWidgets('saved team CRUD works', (tester) async {
      final db = DriftAppDatabase(NativeDatabase.memory());
      addTearDown(() async {
        try { await db.close(); } catch (_) {}
      });

      await db.growthDao.teamSave(
        id: 't1',
        userId: 'local',
        name: 'Test Team',
        membersJson: '[{"characterId":"10000002","buildId":null,"position":0}]',
        notes: 'My team',
      );

      final teams = await db.growthDao.teamsGetAll('local');
      expect(teams.length, 1);
      expect(teams.first.name, 'Test Team');
      expect(teams.first.membersJson, contains('10000002'));

      await db.growthDao.teamDelete('t1');
      final afterDelete = await db.growthDao.teamsGetAll('local');
      expect(afterDelete, isEmpty);

      await db.close();
    });
  });
}
