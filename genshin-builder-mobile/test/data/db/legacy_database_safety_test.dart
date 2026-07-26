import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:genshin_builder_mobile/data/db/database_open_exception.dart';
import 'package:genshin_builder_mobile/data/db/database_path.dart';
import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';
import 'package:genshin_builder_mobile/data/db/drift/daos/growth_dao.dart';
import 'package:genshin_builder_mobile/domain/models/bookmark.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';

const _localUuid = '11111111-1111-4111-8111-111111111111';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('genshin-db-safety-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('real v7 file migrates legacy user data to v8 without loss', () async {
    final file = File(p.join(tempDir.path, 'legacy-v7.db'));
    await _createAndSeedV7(file);

    final db = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );
    await _verifyMigratedData(db);
    await db.close();

    final reopened = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );
    await _verifyMigratedData(reopened);
    expect(await reopened.growthDao.eventsGetByUser(_localUuid), hasLength(1));
    await reopened.close();
  });

  test('migration failure rolls back data and can be retried', () async {
    final file = File(p.join(tempDir.path, 'migration-failure.db'));
    await _createAndSeedV7(file);

    await expectLater(
      DriftAppDatabase.open(
        fileOverride: file,
        createInBackground: false,
        migrationFaultHook: (point) {
          if (point == DatabaseMigrationPoint.afterLegacyGoals) {
            throw StateError('forced migration failure');
          }
        },
      ),
      throwsA(
        isA<DatabaseOpenException>().having(
          (e) => e.kind,
          'kind',
          DatabaseFailureKind.migration,
        ),
      ),
    );

    final raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 7);
    expect(
      raw
          .select(
            "SELECT user_id FROM user_progress WHERE id = 'progress-legacy'",
          )
          .single['user_id'],
      'local',
    );
    expect(
      raw
          .select("SELECT user_id FROM growth_goals WHERE id = 'goal-legacy'")
          .single['user_id'],
      'local',
    );
    raw.dispose();

    final retried = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );
    await _verifyMigratedData(retried);
    await retried.close();
  });

  test('schema DDL failure leaves v6 schema and version unchanged', () async {
    final file = File(p.join(tempDir.path, 'schema-failure.db'));
    _createMinimalV6(file);

    await expectLater(
      DriftAppDatabase.open(
        fileOverride: file,
        createInBackground: false,
        migrationFaultHook: (point) {
          if (point == DatabaseMigrationPoint.afterGrowthGoalsTable) {
            throw StateError('forced schema migration failure');
          }
        },
      ),
      throwsA(
        isA<DatabaseOpenException>().having(
          (e) => e.kind,
          'kind',
          DatabaseFailureKind.migration,
        ),
      ),
    );

    var raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 6);
    expect(
      raw.select("SELECT name FROM sqlite_master WHERE name = 'growth_goals'"),
      isEmpty,
    );
    raw.dispose();

    final retried = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );
    await retried.close();

    raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 9);
    for (final table in [
      'growth_goals',
      'user_material_inventory',
      'saved_teams',
      'growth_events',
      'daily_plan_completions',
      'daily_plan_eval_history',
    ]) {
      expect(
        raw.select('SELECT name FROM sqlite_master WHERE name = ?', [table]),
        hasLength(1),
      );
    }
    raw.dispose();
  });

  test('downgrade is rejected without changing file contents', () async {
    final file = File(p.join(tempDir.path, 'future.db'));
    final current = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );
    await current.progressDao.setSetting('sentinel', 'preserved');
    await current.close();

    var raw = sqlite.sqlite3.open(file.path);
    raw.execute('CREATE TABLE future_marker (value TEXT NOT NULL)');
    raw.execute("INSERT INTO future_marker VALUES ('future-data')");
    raw.userVersion = 10;
    raw.dispose();

    await expectLater(
      DriftAppDatabase.open(fileOverride: file, createInBackground: false),
      throwsA(
        isA<DatabaseOpenException>().having(
          (e) => e.kind,
          'kind',
          DatabaseFailureKind.downgrade,
        ),
      ),
    );

    raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 10);
    expect(
      raw
          .select("SELECT value FROM app_settings WHERE key = 'sentinel'")
          .single['value'],
      'preserved',
    );
    expect(
      raw.select('SELECT value FROM future_marker').single['value'],
      'future-data',
    );
    raw.dispose();
  });

  test('corrupt database is classified and never replaced', () async {
    final file = File(p.join(tempDir.path, 'corrupt.db'));
    final original = utf8.encode('this is not a sqlite database');
    await file.writeAsBytes(original, flush: true);

    await expectLater(
      DriftAppDatabase.open(fileOverride: file, createInBackground: false),
      throwsA(
        isA<DatabaseOpenException>().having(
          (e) => e.kind,
          'kind',
          DatabaseFailureKind.corrupt,
        ),
      ),
    );

    expect(await file.readAsBytes(), original);
  });

  test('busy timeout is finite and lock does not delete data', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });
    final file = File(p.join(tempDir.path, 'locked.db'));
    final db1 = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
      busyTimeout: const Duration(milliseconds: 100),
    );
    final db2 = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
      busyTimeout: const Duration(milliseconds: 100),
    );

    Object? lockError;
    final stopwatch = Stopwatch()..start();
    await db1.transaction(() async {
      await db1.progressDao.setSetting('lock-holder', 'preserved');
      try {
        await db2.progressDao.setSetting('contender', 'not-written');
      } catch (error) {
        lockError = error;
      }
    });
    stopwatch.stop();

    expect(
      lockError,
      isA<sqlite.SqliteException>().having(
        (e) => e.resultCode,
        'resultCode',
        anyOf(5, 6),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(await db1.progressDao.getSetting('lock-holder'), 'preserved');
    expect(await db1.progressDao.getSetting('contender'), isNull);
    await db2.close();
    await db1.close();
    expect(await file.exists(), isTrue);
  });

  test('legacy path copy is atomic and retains the source', () async {
    final source = File(p.join(tempDir.path, 'legacy.db'));
    final destination = File(p.join(tempDir.path, 'new', 'database.db'));
    final bytes = List<int>.generate(4096, (index) => index % 251);
    await source.writeAsBytes(bytes, flush: true);

    final copied = await copyDatabaseFileAtomically(source, destination);

    expect(copied.path, destination.path);
    expect(await copied.readAsBytes(), bytes);
    expect(await source.readAsBytes(), bytes);
    expect(
      tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.contains('.copying-')),
      isEmpty,
    );
  });
}

class _Version7Database extends DriftAppDatabase {
  _Version7Database(File file) : super(NativeDatabase(file));

  @override
  int get schemaVersion => 7;
}

Future<void> _createAndSeedV7(File file) async {
  final db = _Version7Database(file);
  await db.customStatement('SELECT 1');
  await db.progressDao.setSetting('local_user_id', _localUuid);
  await db.characterDao.upsertCharacter(
    const MasterCharacter(
      id: '10000002',
      name: 'Legacy Character',
      element: 'cryo',
      weaponType: 'sword',
      rarity: 5,
      region: 'Inazuma',
      iconUrl: '',
    ),
  );
  await db.progressDao.upsertProgress(
    const UserProgress(
      id: 'progress-legacy',
      userId: 'local',
      characterId: '10000002',
      level: 80,
      ascension: 5,
      constellation: 2,
      talentNormal: 8,
      talentSkill: 9,
      talentBurst: 10,
      weaponId: 'weapon-legacy',
      weaponName: 'Legacy Weapon',
      weaponLevel: 90,
      weaponRefinement: 3,
      artifactsJson: '{"flower":{"level":20}}',
      artifactCompleted: true,
      memo: 'preserve me',
      artifactScoreType: 'atk',
    ),
  );
  await db.bookmarkDao.upsertBookmark(
    const MaterialBookmarkEntry(
      id: 'bookmark-legacy',
      sourceKey: 'character:10000002:level:80-90',
      sourceLabel: 'Legacy material plan',
      materialId: 'material-legacy',
      name: 'Legacy Material',
      count: 12,
      characterId: '10000002',
      characterName: 'Legacy Character',
      addedAt: 123456,
    ),
  );
  await db.growthDao.goalSave(
    id: 'goal-legacy',
    userId: 'local',
    characterId: '10000002',
    targetLevel: 90,
    targetAscension: 6,
    targetTalentBurst: 10,
  );
  await db.growthDao.inventorySetQuantity('local', 'material-legacy', 42);
  await db.growthDao.teamSave(
    id: 'team-legacy',
    userId: 'local',
    name: 'Legacy Team',
    membersJson:
        '[{"characterId":"10000002","buildId":"progress-legacy","position":0}]',
  );
  await db.growthDao.eventsSaveAll([
    EventParams(
      eventId: 'event-legacy',
      userId: 'local',
      characterId: '10000002',
      eventType: 'characterLevelChanged',
      beforeValue: '70',
      afterValue: '80',
      source: 'localManual',
      observedAt: 123456,
      dedupKey: 'local:10000002:characterLevelChanged:70->80',
    ),
  ]);
  await db.close();

  // createAll on a Version7 subclass also creates newer tables from the shared
  // Drift schema; drop them so onUpgrade from < 9 can create them cleanly.
  final raw = sqlite.sqlite3.open(file.path);
  raw.execute('DROP TABLE IF EXISTS daily_plan_completions');
  raw.execute('DROP TABLE IF EXISTS daily_plan_eval_history');
  raw.userVersion = 7;
  raw.dispose();
}

Future<void> _verifyMigratedData(DriftAppDatabase db) async {
  expect(
    (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    ),
    9,
  );
  expect(await db.progressDao.getSetting('local_user_id'), _localUuid);

  final progress = await db.progressDao.getProgress(_localUuid, '10000002');
  expect(progress, isNotNull);
  expect(progress!.level, 80);
  expect(progress.ascension, 5);
  expect(progress.talentSkill, 9);
  expect(progress.weaponLevel, 90);
  expect(progress.weaponRefinement, 3);
  expect(progress.artifactsJson, '{"flower":{"level":20}}');
  expect(progress.artifactCompleted, isTrue);
  expect(await db.progressDao.getProgress('local', '10000002'), isNull);

  final bookmarks = await db.bookmarkDao.getAllBookmarks();
  expect(bookmarks, hasLength(1));
  expect(bookmarks.single.id, 'bookmark-legacy');
  expect(bookmarks.single.count, 12);

  final goals = await db.growthDao.goalsGetAll(_localUuid);
  expect(goals, hasLength(1));
  expect(goals.single.id, 'goal-legacy');
  expect(goals.single.targetLevel, 90);

  final inventory = await db.growthDao.inventoryGet(_localUuid);
  expect(inventory, hasLength(1));
  expect(inventory.single.quantity, 42);

  final teams = await db.growthDao.teamsGetAll(_localUuid);
  expect(teams, hasLength(1));
  expect(teams.single.membersJson, contains('progress-legacy'));
  expect(teams.single.membersJson, contains('10000002'));

  final events = await db.growthDao.eventsGetByUser(_localUuid);
  expect(events, hasLength(1));
  expect(events.single.characterId, '10000002');
  expect(events.single.eventId, 'event-legacy');

  for (final table in [
    'daily_plan_completions',
    'daily_plan_eval_history',
  ]) {
    expect(
      await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            variables: [Variable<String>(table)],
          )
          .get(),
      hasLength(1),
    );
  }
}

void _createMinimalV6(File file) {
  final db = sqlite.sqlite3.open(file.path);
  db.execute('''
    CREATE TABLE app_settings (
      "key" TEXT NOT NULL PRIMARY KEY,
      "value" TEXT NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE user_progress (
      id TEXT NOT NULL PRIMARY KEY,
      user_id TEXT NOT NULL,
      character_id TEXT NOT NULL,
      level INTEGER NOT NULL DEFAULT 1,
      ascension INTEGER NOT NULL DEFAULT 0,
      constellation INTEGER NOT NULL DEFAULT 0,
      talent_normal INTEGER NOT NULL DEFAULT 1,
      talent_skill INTEGER NOT NULL DEFAULT 1,
      talent_burst INTEGER NOT NULL DEFAULT 1,
      weapon_id TEXT NOT NULL DEFAULT '',
      weapon_name TEXT NOT NULL DEFAULT '',
      weapon_level INTEGER NOT NULL DEFAULT 1,
      weapon_refinement INTEGER NOT NULL DEFAULT 1,
      artifacts TEXT NOT NULL DEFAULT '{}',
      artifact_score_type TEXT NOT NULL DEFAULT '',
      is_completed INTEGER NOT NULL DEFAULT 0,
      memo TEXT NOT NULL DEFAULT '',
      updated_at INTEGER NOT NULL,
      UNIQUE(user_id, character_id)
    )
  ''');
  db.execute('''
    CREATE TABLE character_upgrades (
      character_id TEXT NOT NULL PRIMARY KEY,
      promotes TEXT NOT NULL,
      talents TEXT NOT NULL,
      content_hash TEXT NOT NULL DEFAULT '',
      synced_at INTEGER NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE weapon_upgrades (
      weapon_id TEXT NOT NULL PRIMARY KEY,
      promotes TEXT NOT NULL,
      level_up_item_ids TEXT NOT NULL DEFAULT '[]',
      content_hash TEXT NOT NULL DEFAULT '',
      synced_at INTEGER NOT NULL
    )
  ''');
  db.userVersion = 6;
  db.dispose();
}
