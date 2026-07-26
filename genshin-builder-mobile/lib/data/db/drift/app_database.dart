import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' show Database, SqliteException;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:uuid/uuid.dart';

import '../../secure/secure_storage_service.dart';
import '../database_open_exception.dart';
import '../database_path.dart';
import 'daos/bookmark_dao.dart';
import 'daos/battle_statistics_dao.dart';
import 'daos/character_dao.dart';
import 'daos/growth_dao.dart';
import 'daos/progress_dao.dart';
import 'tables/growth_tables.dart';
import 'tables/battle_statistics_tables.dart';
import 'tables/master_tables.dart';
import 'tables/user_tables.dart';

part 'app_database.g.dart';

/// `--dart-define=ENABLE_SQLCIPHER=true` のときのみ SQLCipher + PRAGMA key を使う。
/// 既定は false（既存の平文 DB を壊さない）。
const bool kEnableSqlCipher = bool.fromEnvironment(
  'ENABLE_SQLCIPHER',
  defaultValue: false,
);

const Duration kDatabaseBusyTimeout = Duration(seconds: 5);

enum DatabaseMigrationPoint {
  beforeUpgrade,
  afterGrowthGoalsTable,
  afterGrowthTables,
  afterLegacyProgress,
  afterLegacyGoals,
  afterLegacyInventory,
  afterLegacyTeams,
  afterLegacyEvents,
  beforeCommit,
}

typedef DatabaseMigrationFaultHook =
    FutureOr<void> Function(DatabaseMigrationPoint point);

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
    GrowthGoals,
    UserMaterialInventory,
    SavedTeams,
    GrowthEvents,
    RemoteBattleStatsManifests,
    RemoteBattleTeams,
    RemoteBattleTeamMembers,
    RemoteBattleCharacterUsages,
    RemoteBattleSyncStates,
  ],
  daos: [
    CharacterDao,
    BookmarkDao,
    ProgressDao,
    GrowthDao,
    BattleStatisticsDao,
  ],
)
class DriftAppDatabase extends _$DriftAppDatabase {
  DriftAppDatabase(
    super.e, {
    DatabaseMigrationFaultHook? migrationFaultHook,
    Duration busyTimeout = kDatabaseBusyTimeout,
  }) : _migrationFaultHook = migrationFaultHook,
       _busyTimeout = busyTimeout;

  static const _dbName = 'genshin_builder.db';
  static const _legacyLocalUserId = 'local';

  final DatabaseMigrationFaultHook? _migrationFaultHook;
  final Duration _busyTimeout;

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(m);
      await _createGrowthIndexes(m.database);
      await _createBattleStatisticsIndexes(m.database);
    },
    onUpgrade: (m, from, to) async {
      if (from > to) {
        throw const DatabaseOpenException(DatabaseFailureKind.downgrade);
      }

      try {
        await m.database.transaction(() async {
          await _migrationCheckpoint(DatabaseMigrationPoint.beforeUpgrade);
          if (from < 2) {
            await m.createTable(appSettings);
          }
          if (from < 4) {
            await _addArtifactsColumnSafely(m.database);
          }
          if (from < 5) {
            await _addArtifactScoreTypeColumnSafely(m.database);
          }
          if (from < 6) {
            await _addUpgradeContentHashColumnsSafely(m.database);
          }
          if (from < 7) {
            await m.createTable(growthGoals);
            await _migrationCheckpoint(
              DatabaseMigrationPoint.afterGrowthGoalsTable,
            );
            await m.createTable(userMaterialInventory);
            await m.createTable(savedTeams);
            await m.createTable(growthEvents);
            await _createGrowthIndexes(m.database);
            await _migrationCheckpoint(
              DatabaseMigrationPoint.afterGrowthTables,
            );
          }
          if (from < 8) {
            await _migrateLegacyLocalUserIds(m.database);
          }
          if (from < 9) {
            await m.createTable(remoteBattleStatsManifests);
            await m.createTable(remoteBattleTeams);
            await m.createTable(remoteBattleTeamMembers);
            await m.createTable(remoteBattleCharacterUsages);
            await m.createTable(remoteBattleSyncStates);
            await _createBattleStatisticsIndexes(m.database);
          }
          await _migrationCheckpoint(DatabaseMigrationPoint.beforeCommit);
        });
      } on DatabaseOpenException {
        rethrow;
      } on SqliteException catch (error) {
        throw _classifyDatabaseFailure(error, duringMigration: true);
      } catch (_) {
        throw const DatabaseOpenException(DatabaseFailureKind.migration);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'PRAGMA busy_timeout = ${_busyTimeout.inMilliseconds}',
      );
      await transaction(() async {
        await _addArtifactsColumnSafely(this);
        await _addArtifactScoreTypeColumnSafely(this);
        await _addUpgradeContentHashColumnsSafely(this);
      });
    },
  );

  Future<void> _migrationCheckpoint(DatabaseMigrationPoint point) async {
    await _migrationFaultHook?.call(point);
  }

  Future<void> _migrateLegacyLocalUserIds(GeneratedDatabase db) async {
    final current =
        await db
            .customSelect(
              'SELECT value FROM app_settings WHERE key = ? LIMIT 1',
              variables: const [Variable<String>('local_user_id')],
            )
            .getSingleOrNull();
    var localUserId = current?.read<String>('value').trim();
    if (localUserId == null ||
        localUserId.isEmpty ||
        localUserId == _legacyLocalUserId) {
      localUserId = const Uuid().v4();
      await db.customStatement(
        'INSERT OR REPLACE INTO app_settings ("key", "value") VALUES (?, ?)',
        ['local_user_id', localUserId],
      );
    }

    // Keep conflicting rows untouched instead of dropping either user's data.
    await db.customStatement(
      '''
      UPDATE user_progress AS legacy
      SET user_id = ?
      WHERE legacy.user_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM user_progress AS current
          WHERE current.user_id = ?
            AND current.character_id = legacy.character_id
        )
      ''',
      [localUserId, _legacyLocalUserId, localUserId],
    );
    await _migrationCheckpoint(DatabaseMigrationPoint.afterLegacyProgress);

    await db.customStatement(
      'UPDATE growth_goals SET user_id = ? WHERE user_id = ?',
      [localUserId, _legacyLocalUserId],
    );
    await _migrationCheckpoint(DatabaseMigrationPoint.afterLegacyGoals);

    await db.customStatement(
      '''
      UPDATE user_material_inventory AS legacy
      SET user_id = ?
      WHERE legacy.user_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM user_material_inventory AS current
          WHERE current.user_id = ?
            AND current.material_id = legacy.material_id
        )
      ''',
      [localUserId, _legacyLocalUserId, localUserId],
    );
    await _migrationCheckpoint(DatabaseMigrationPoint.afterLegacyInventory);

    await db.customStatement(
      'UPDATE saved_teams SET user_id = ? WHERE user_id = ?',
      [localUserId, _legacyLocalUserId],
    );
    await _migrationCheckpoint(DatabaseMigrationPoint.afterLegacyTeams);

    await db.customStatement(
      'UPDATE growth_events SET user_id = ? WHERE user_id = ?',
      [localUserId, _legacyLocalUserId],
    );
    await _migrationCheckpoint(DatabaseMigrationPoint.afterLegacyEvents);
  }

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

  static Future<void> _addUpgradeContentHashColumnsSafely(
    GeneratedDatabase db,
  ) async {
    for (final statement in [
      "ALTER TABLE character_upgrades ADD COLUMN content_hash TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE weapon_upgrades ADD COLUMN content_hash TEXT NOT NULL DEFAULT ''",
    ]) {
      try {
        await db.customStatement(statement);
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('duplicate column')) {
          rethrow;
        }
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

  static Future<void> _createGrowthIndexes(GeneratedDatabase db) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_goals_user ON growth_goals (user_id)',
      'CREATE INDEX IF NOT EXISTS idx_goals_character ON growth_goals (character_id)',
      'CREATE INDEX IF NOT EXISTS idx_inventory_user ON user_material_inventory (user_id)',
      'CREATE INDEX IF NOT EXISTS idx_teams_user ON saved_teams (user_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_events_dedup ON growth_events (dedup_key)',
      'CREATE INDEX IF NOT EXISTS idx_events_user_char ON growth_events (user_id, character_id)',
    ];
    for (final sql in indexes) {
      await db.customStatement(sql);
    }
  }

  static Future<void> _createBattleStatisticsIndexes(
    GeneratedDatabase db,
  ) async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS idx_remote_battle_teams_type_usage '
          'ON remote_battle_teams (content_type, usage_rate)',
      'CREATE INDEX IF NOT EXISTS idx_remote_battle_members_character '
          'ON remote_battle_team_members (character_id, team_id)',
      'CREATE INDEX IF NOT EXISTS idx_remote_battle_characters_type_usage '
          'ON remote_battle_character_usages (content_type, usage_rate)',
    ]) {
      await db.customStatement(sql);
    }
  }

  /// ネイティブ SQLCipher をロード（平文利用時も必須。鍵は別途 PRAGMA）。
  static Future<void> _setupSqlCipherIsolate() async {
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      sqlite3_open.open.overrideFor(
        sqlite3_open.OperatingSystem.android,
        openCipherOnAndroid,
      );
    }
  }

  static DatabaseOpenException _classifyDatabaseFailure(
    Object error, {
    bool duringMigration = false,
  }) {
    if (error is DatabaseOpenException) return error;
    if (error is SqliteException) {
      return DatabaseOpenException(switch (error.resultCode) {
        5 || 6 => DatabaseFailureKind.locked,
        8 => DatabaseFailureKind.readOnly,
        10 || 14 => DatabaseFailureKind.io,
        11 || 26 => DatabaseFailureKind.corrupt,
        13 => DatabaseFailureKind.diskFull,
        _ =>
          duringMigration
              ? DatabaseFailureKind.migration
              : DatabaseFailureKind.unknown,
      });
    }

    // Background-isolate errors are transported as remote exceptions.
    final message = error.toString().toLowerCase();
    if (message.contains('database_downgrade')) {
      return const DatabaseOpenException(DatabaseFailureKind.downgrade);
    }
    if (message.contains('database_migration')) {
      return const DatabaseOpenException(DatabaseFailureKind.migration);
    }
    if (message.contains('database is locked') ||
        message.contains('database is busy')) {
      return const DatabaseOpenException(DatabaseFailureKind.locked);
    }
    if (message.contains('database disk image is malformed') ||
        message.contains('file is not a database')) {
      return const DatabaseOpenException(DatabaseFailureKind.corrupt);
    }
    if (message.contains('readonly')) {
      return const DatabaseOpenException(DatabaseFailureKind.readOnly);
    }
    if (message.contains('disk is full')) {
      return const DatabaseOpenException(DatabaseFailureKind.diskFull);
    }
    if (message.contains('disk i/o') || message.contains('unable to open')) {
      return const DatabaseOpenException(DatabaseFailureKind.io);
    }
    return DatabaseOpenException(
      duringMigration
          ? DatabaseFailureKind.migration
          : DatabaseFailureKind.unknown,
    );
  }

  static Future<DriftAppDatabase> open({
    SecureStorageService? secureStorage,
    File? fileOverride,
    bool createInBackground = true,
    DatabaseMigrationFaultHook? migrationFaultHook,
    Duration busyTimeout = kDatabaseBusyTimeout,
  }) async {
    // sqlcipher_flutter_libs のみ依存のため、常にネイティブを差し替える。
    await _setupSqlCipherIsolate();

    final file = fileOverride ?? await resolveDatabaseFile(_dbName);

    String? encryptionKey;
    if (kEnableSqlCipher) {
      final storage = secureStorage ?? SecureStorageService();
      encryptionKey = await storage.getOrCreateDbKey();
    }

    void setupDatabase(Database rawDb) {
      if (encryptionKey != null) {
        final escaped = encryptionKey.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escaped'");
      }
      rawDb.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
    }

    final executor =
        createInBackground
            ? NativeDatabase.createInBackground(
              file,
              isolateSetup: _setupSqlCipherIsolate,
              setup: setupDatabase,
            )
            : NativeDatabase(file, setup: setupDatabase);
    final db = DriftAppDatabase(
      executor,
      migrationFaultHook: migrationFaultHook,
      busyTimeout: busyTimeout,
    );
    try {
      // Opening waits for migration and beforeOpen to finish.
      await db.customStatement('SELECT 1');
      return db;
    } catch (error) {
      try {
        await db.close();
      } catch (_) {
        // Preserve the original classified failure.
      }
      throw _classifyDatabaseFailure(error);
    }
  }

  /// テスト用インメモリ DB
  static Future<DriftAppDatabase> openInMemory() async {
    final db = DriftAppDatabase(NativeDatabase.memory());
    await db.customStatement('SELECT 1');
    return db;
  }
}
