import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';
import 'package:genshin_builder_mobile/domain/battle_statistics/battle_statistics.dart';

void main() {
  test('schema v9 creates remote battle statistics tables', () async {
    final db = await DriftAppDatabase.openInMemory();
    addTearDown(db.close);

    for (final table in [
      'remote_battle_stats_manifests',
      'remote_battle_teams',
      'remote_battle_team_members',
      'remote_battle_character_usages',
      'remote_battle_sync_states',
    ]) {
      final row =
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                variables: [Variable<String>(table)],
              )
              .getSingleOrNull();
      expect(row, isNotNull, reason: '$table must exist');
    }
  });

  test('v8 database is upgraded additively to v9', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA user_version = 8');
        raw.execute(
          'CREATE TABLE user_progress ('
          'id TEXT PRIMARY KEY, artifacts TEXT NOT NULL DEFAULT "{}", '
          'artifact_score_type TEXT NOT NULL DEFAULT "")',
        );
        raw.execute(
          'CREATE TABLE character_upgrades ('
          'character_id TEXT PRIMARY KEY, content_hash TEXT NOT NULL DEFAULT "")',
        );
        raw.execute(
          'CREATE TABLE weapon_upgrades ('
          'weapon_id TEXT PRIMARY KEY, content_hash TEXT NOT NULL DEFAULT "")',
        );
      },
    );
    final db = DriftAppDatabase(executor);
    addTearDown(db.close);

    await db.customStatement('SELECT 1');
    final row =
        await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type='table' AND name='remote_battle_stats_manifests'",
            )
            .getSingleOrNull();
    expect(row, isNotNull);
  });

  test('failed outer transaction preserves the prior revision', () async {
    final db = await DriftAppDatabase.openInMemory();
    addTearDown(db.close);
    await db.battleStatisticsDao.replaceBundle(_bundle(revision: 1));

    await expectLater(
      db.transaction(() async {
        await db.battleStatisticsDao.replaceBundle(_bundle(revision: 2));
        throw const FormatException('fault after replacement');
      }),
      throwsFormatException,
    );

    final manifest = await db.battleStatisticsDao.readManifest('abyss');
    expect(manifest?.revision, 1);
    final teams = await db.battleStatisticsDao.readTeams('abyss');
    expect(teams.single.usageRate, 0.1);
  });
}

BattleStatsBundle _bundle({required int revision}) => BattleStatsBundle(
  schemaVersion: 1,
  contentType: BattleStatsContentType.abyss,
  sourceVersion: 'fixture',
  seasonId: 'season',
  revision: revision,
  payloadHash:
      'sha256:0000000000000000000000000000000000000000000000000000000000000000',
  sourceUpdatedAt: DateTime.utc(2026, 7, 24),
  teams: [
    RemoteBattleTeam(
      teamKey: '1:2:3:4',
      members: const ['1', '2', '3', '4'],
      usageRate: revision == 1 ? 0.1 : 0.2,
    ),
  ],
  characters: const [
    RemoteBattleCharacterUsage(characterId: '1', usageRate: 0.1),
  ],
);
