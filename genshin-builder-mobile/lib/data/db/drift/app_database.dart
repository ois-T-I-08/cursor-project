import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../database_path.dart';
import 'daos/bookmark_dao.dart';
import 'daos/character_dao.dart';
import 'daos/progress_dao.dart';
import 'tables/master_tables.dart';
import 'tables/user_tables.dart';

part 'app_database.g.dart';

/// Drift SQLite（レガシー sqflite と同一パスを [database_path] で解決）
@DriftDatabase(
  tables: [
    Characters,
    Weapons,
    Materials,
    CharacterUpgrades,
    WeaponUpgrades,
    LevelExpSegments,
    UserProgressTable,
    MaterialBookmarks,
    SyncLogs,
    AppSettings,
  ],
  daos: [CharacterDao, BookmarkDao, ProgressDao],
)
class DriftAppDatabase extends _$DriftAppDatabase {
  DriftAppDatabase(super.e);

  static const _dbName = 'genshin_builder.db';

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettings);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static Future<void> _createIndexes(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_bookmarks_material '
      'ON material_bookmarks (material_id)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_progress_user '
      'ON user_progress (user_id)',
    );
  }

  static Future<DriftAppDatabase> open() async {
    final file = await resolveDatabaseFile(_dbName);
    return DriftAppDatabase(NativeDatabase.createInBackground(file));
  }
}
