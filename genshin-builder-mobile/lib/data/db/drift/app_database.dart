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
  int get schemaVersion => 5;

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
          if (from < 4) {
            await _addArtifactsColumnSafely(m.database);
          }
          if (from < 5) {
            await _addArtifactScoreTypeColumnSafely(m.database);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _addArtifactsColumnSafely(this);
          await _addArtifactScoreTypeColumnSafely(this);
        },
      );

  /// `artifacts` 列が無い DB を修復（重複追加は無視）
  static Future<void> _addArtifactsColumnSafely(GeneratedDatabase db) async {
    try {
      await db.customStatement(
        "ALTER TABLE user_progress ADD COLUMN artifacts TEXT NOT NULL DEFAULT '{}'",
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('duplicate column')) {
        rethrow;
      }
    }
  }

  static Future<void> _addArtifactScoreTypeColumnSafely(
    GeneratedDatabase db,
  ) async {
    try {
      await db.customStatement(
        "ALTER TABLE user_progress ADD COLUMN artifact_score_type TEXT NOT NULL DEFAULT ''",
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('duplicate column')) {
        rethrow;
      }
    }
  }

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
    final db = DriftAppDatabase(NativeDatabase.createInBackground(file));
    // マイグレーション完了を待ってから列修復（createInBackground 対策）
    await db.customStatement('SELECT 1');
    await _addArtifactsColumnSafely(db);
    await _addArtifactScoreTypeColumnSafely(db);
    return db;
  }

  /// テスト用インメモリ DB
  static Future<DriftAppDatabase> openInMemory() async {
    final db = DriftAppDatabase(NativeDatabase.memory());
    await db.customStatement('SELECT 1');
    return db;
  }
}
