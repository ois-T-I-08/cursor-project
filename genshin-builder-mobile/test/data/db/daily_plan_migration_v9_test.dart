import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';
import 'package:genshin_builder_mobile/domain/models/bookmark.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';

const _userId = '22222222-2222-4222-8222-222222222222';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('genshin-db-v9-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('real v8 file migrates to v9 creating daily plan tables without loss',
      () async {
    final file = File(p.join(tempDir.path, 'legacy-v8.db'));
    await _createAndSeedV8(file);

    final db = await DriftAppDatabase.open(
      fileOverride: file,
      createInBackground: false,
    );

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version');
    expect(version, 9);

    for (final table in [
      'daily_plan_completions',
      'daily_plan_eval_history',
    ]) {
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
            )
            .get(),
        hasLength(1),
      );
    }

    expect(await db.progressDao.getSetting('local_user_id'), _userId);
    expect(await db.progressDao.getSetting('sentinel_v8'), 'keep-me');
    final progress = await db.progressDao.getProgress(_userId, '10000002');
    expect(progress, isNotNull);
    expect(progress!.level, 70);
    final goals = await db.growthDao.goalsGetAll(_userId);
    expect(goals, hasLength(1));
    expect(goals.single.id, 'goal-v8');
    final bookmarks = await db.bookmarkDao.getAllBookmarks();
    expect(bookmarks, hasLength(1));

    // New tables start empty; v8 rows untouched.
    final completions = await db.dailyPlanDao.completionsForDate(
      userId: _userId,
      localDate: '2026-07-15',
    );
    expect(completions, isEmpty);

    await db.close();
  });
}

Future<void> _createAndSeedV8(File file) async {
  final db = await DriftAppDatabase.open(
    fileOverride: file,
    createInBackground: false,
  );
  await db.progressDao.setSetting('local_user_id', _userId);
  await db.progressDao.setSetting('sentinel_v8', 'keep-me');
  await db.characterDao.upsertCharacter(
    const MasterCharacter(
      id: '10000002',
      name: 'V8 Character',
      element: 'cryo',
      weaponType: 'sword',
      rarity: 5,
      region: 'Inazuma',
      iconUrl: '',
    ),
  );
  await db.progressDao.upsertProgress(
    const UserProgress(
      id: 'progress-v8',
      userId: _userId,
      characterId: '10000002',
      level: 70,
      ascension: 4,
      constellation: 0,
      talentNormal: 6,
      talentSkill: 6,
      talentBurst: 6,
      weaponId: 'weapon-v8',
      weaponName: 'V8 Weapon',
      weaponLevel: 80,
      weaponRefinement: 1,
      artifactsJson: '{}',
      artifactCompleted: false,
      memo: 'v8',
      artifactScoreType: '',
    ),
  );
  await db.bookmarkDao.upsertBookmark(
    const MaterialBookmarkEntry(
      id: 'bookmark-v8',
      sourceKey: 'character:10000002:level:70-80',
      sourceLabel: 'V8 plan',
      materialId: 'material-v8',
      name: 'V8 Material',
      count: 3,
      characterId: '10000002',
      characterName: 'V8 Character',
      addedAt: 999,
    ),
  );
  await db.growthDao.goalSave(
    id: 'goal-v8',
    userId: _userId,
    characterId: '10000002',
    targetLevel: 90,
  );
  await db.close();

  final raw = sqlite.sqlite3.open(file.path);
  raw.execute('DROP TABLE IF EXISTS daily_plan_completions');
  raw.execute('DROP TABLE IF EXISTS daily_plan_eval_history');
  raw.userVersion = 8;
  raw.dispose();
}
