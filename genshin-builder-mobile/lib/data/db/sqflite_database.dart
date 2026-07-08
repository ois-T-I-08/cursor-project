import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/bookmark.dart';
import '../../domain/models/calculation_models.dart';
import '../models/master_models.dart';
import 'upgrade_serde.dart';

/// sqflite 実装（Drift codegen 完了までの暫定 DB）
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;
  static const _dbName = 'genshin_builder.db';
  static const _dbVersion = 2;

  static Future<AppDatabase> open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE characters (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            element TEXT NOT NULL,
            weapon_type TEXT NOT NULL,
            rarity INTEGER NOT NULL,
            region TEXT NOT NULL,
            icon_url TEXT NOT NULL,
            score_type TEXT NOT NULL DEFAULT 'atk',
            synced_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE weapons (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            weapon_type TEXT NOT NULL,
            rarity INTEGER NOT NULL,
            icon_url TEXT NOT NULL,
            synced_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE materials (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            rarity INTEGER,
            icon_url TEXT NOT NULL,
            exp_value INTEGER,
            exp_target TEXT,
            synced_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE character_upgrades (
            character_id TEXT PRIMARY KEY,
            promotes TEXT NOT NULL,
            talents TEXT NOT NULL,
            synced_at INTEGER NOT NULL,
            FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE weapon_upgrades (
            weapon_id TEXT PRIMARY KEY,
            promotes TEXT NOT NULL,
            level_up_item_ids TEXT NOT NULL DEFAULT '[]',
            synced_at INTEGER NOT NULL,
            FOREIGN KEY (weapon_id) REFERENCES weapons(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE level_exp_segments (
            id TEXT PRIMARY KEY,
            target_type TEXT NOT NULL,
            rarity INTEGER NOT NULL DEFAULT 0,
            from_level INTEGER NOT NULL,
            to_level INTEGER NOT NULL,
            exp_required INTEGER NOT NULL,
            mora_required INTEGER NOT NULL DEFAULT 0,
            synced_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE user_progress (
            id TEXT PRIMARY KEY,
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
            is_completed INTEGER NOT NULL DEFAULT 0,
            memo TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL,
            UNIQUE(user_id, character_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE material_bookmarks (
            id TEXT PRIMARY KEY,
            source_key TEXT NOT NULL,
            source_label TEXT NOT NULL,
            material_id TEXT NOT NULL,
            name TEXT NOT NULL,
            count INTEGER NOT NULL,
            icon_url TEXT,
            character_id TEXT,
            character_name TEXT,
            character_icon_url TEXT,
            character_emoji TEXT,
            added_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            status TEXT NOT NULL,
            detail TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_bookmarks_material ON material_bookmarks(material_id)',
        );
        await db.execute(
          'CREATE INDEX idx_progress_user ON user_progress(user_id)',
        );
      },
    );
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  /// マスタ同期などの一括書き込み用
  Future<void> upsertCharactersBatch(List<MasterCharacter> list) async {
    final batch = _db.batch();
    for (final c in list) {
      batch.insert(
        'characters',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertWeaponsBatch(List<MasterWeapon> list) async {
    final batch = _db.batch();
    for (final w in list) {
      batch.insert(
        'weapons',
        w.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertMaterialsBatch(List<MasterMaterial> list) async {
    final batch = _db.batch();
    for (final m in list) {
      batch.insert(
        'materials',
        m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // --- Characters ---

  Future<void> upsertCharacter(MasterCharacter c) async {
    await _db.insert(
      'characters',
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MasterCharacter>> getAllCharacters() async {
    final rows = await _db.query('characters', orderBy: 'name ASC');
    return rows.map((r) => MasterCharacter.fromMap(r)).toList();
  }

  Future<MasterCharacter?> getCharacter(String id) async {
    final rows =
        await _db.query('characters', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MasterCharacter.fromMap(rows.first);
  }

  // --- Weapons ---

  Future<void> upsertWeapon(MasterWeapon w) async {
    await _db.insert(
      'weapons',
      w.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MasterWeapon?> getWeapon(String id) async {
    final rows = await _db.query('weapons', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MasterWeapon.fromMap(rows.first);
  }

  // --- Materials ---

  Future<void> upsertMaterial(MasterMaterial m) async {
    await _db.insert(
      'materials',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MasterMaterial>> getAllMaterials() async {
    final rows = await _db.query('materials', orderBy: 'name ASC');
    return rows.map((r) => MasterMaterial.fromMap(r)).toList();
  }

  Future<MasterMaterial?> getMaterial(String id) async {
    final rows =
        await _db.query('materials', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MasterMaterial.fromMap(rows.first);
  }

  Future<Map<String, MasterMaterial>> getMaterialsMap() async {
    final all = await getAllMaterials();
    return {for (final m in all) m.id: m};
  }

  // --- Upgrades ---

  Future<void> upsertCharacterUpgrade({
    required String characterId,
    required List<PromoteStage> promotes,
    required Map<String, List<TalentLevelUpgrade>> talents,
  }) async {
    await _db.insert(
      'character_upgrades',
      {
        'character_id': characterId,
        'promotes': jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList()),
        'talents': jsonEncode(
          talents.map(
            (key, value) =>
                MapEntry(key, value.map(UpgradeSerde.talentToJson).toList()),
          ),
        ),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({
    List<PromoteStage> promotes,
    Map<String, List<TalentLevelUpgrade>> talents,
  })?> getCharacterUpgrade(String characterId) async {
    final rows = await _db.query(
      'character_upgrades',
      where: 'character_id = ?',
      whereArgs: [characterId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final promotesRaw = jsonDecode(row['promotes']! as String) as List;
    final talentsRaw =
        jsonDecode(row['talents']! as String) as Map<String, dynamic>;
    return (
      promotes: promotesRaw
          .map((e) => UpgradeSerde.promoteFromJson(e as Map<String, dynamic>))
          .toList(),
      talents: talentsRaw.map(
        (key, value) => MapEntry(
          key,
          (value as List)
              .map((e) => UpgradeSerde.talentFromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      ),
    );
  }

  Future<void> upsertWeaponUpgrade({
    required String weaponId,
    required List<PromoteStage> promotes,
    required List<String> levelUpItemIds,
  }) async {
    await _db.insert(
      'weapon_upgrades',
      {
        'weapon_id': weaponId,
        'promotes': jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList()),
        'level_up_item_ids': jsonEncode(levelUpItemIds),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
      getWeaponUpgrade(String weaponId) async {
    final rows = await _db.query(
      'weapon_upgrades',
      where: 'weapon_id = ?',
      whereArgs: [weaponId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final promotesRaw = jsonDecode(row['promotes']! as String) as List;
    final itemIds =
        (jsonDecode(row['level_up_item_ids']! as String) as List).cast<String>();
    return (
      promotes: promotesRaw
          .map((e) => UpgradeSerde.promoteFromJson(e as Map<String, dynamic>))
          .toList(),
      levelUpItemIds: itemIds,
    );
  }

  // --- Progress ---

  Future<void> upsertProgress(UserProgress p) async {
    await _db.insert(
      'user_progress',
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserProgress?> getProgress(String userId, String characterId) async {
    final rows = await _db.query(
      'user_progress',
      where: 'user_id = ? AND character_id = ?',
      whereArgs: [userId, characterId],
    );
    if (rows.isEmpty) return null;
    return UserProgress.fromMap(rows.first);
  }

  Future<UserProgress> getOrCreateProgress(
    String userId,
    String characterId,
    String progressId,
  ) async {
    final existing = await getProgress(userId, characterId);
    if (existing != null) return existing;
    final created = UserProgress(
      id: progressId,
      userId: userId,
      characterId: characterId,
    );
    await upsertProgress(created);
    return created;
  }

  // --- Bookmarks ---

  Future<List<MaterialBookmarkEntry>> getAllBookmarks() async {
    final rows =
        await _db.query('material_bookmarks', orderBy: 'added_at DESC');
    return rows.map(_bookmarkFromRow).toList();
  }

  Future<void> upsertBookmark(MaterialBookmarkEntry entry) async {
    await _db.delete(
      'material_bookmarks',
      where: 'source_key = ? AND material_id = ?',
      whereArgs: [entry.sourceKey, entry.materialId],
    );
    await _db.insert('material_bookmarks', _bookmarkToRow(entry));
  }

  Future<void> removeBookmark(String id) async {
    await _db.delete(
      'material_bookmarks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeBookmarksBySourceKey(String sourceKey) async {
    await _db.delete(
      'material_bookmarks',
      where: 'source_key = ?',
      whereArgs: [sourceKey],
    );
  }

  // --- Sync log ---

  Future<void> insertSyncLog(String status, String detail) async {
    await _db.insert('sync_logs', {
      'status': status,
      'detail': detail,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // --- App settings ---

  Future<String?> getSetting(String key) async {
    final rows =
        await _db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DateTime?> getLastSyncTime() async {
    final rows = await _db.query(
      'sync_logs',
      where: "status = 'success'",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['created_at']! as int);
  }

  static Map<String, Object?> _bookmarkToRow(MaterialBookmarkEntry e) => {
        'id': e.id,
        'source_key': e.sourceKey,
        'source_label': e.sourceLabel,
        'material_id': e.materialId,
        'name': e.name,
        'count': e.count,
        'icon_url': e.iconUrl,
        'character_id': e.characterId,
        'character_name': e.characterName,
        'character_icon_url': e.characterIconUrl,
        'character_emoji': e.characterEmoji,
        'added_at': e.addedAt,
      };

  static MaterialBookmarkEntry _bookmarkFromRow(Map<String, Object?> row) =>
      MaterialBookmarkEntry(
        id: row['id']! as String,
        sourceKey: row['source_key']! as String,
        sourceLabel: row['source_label']! as String,
        materialId: row['material_id']! as String,
        name: row['name']! as String,
        count: row['count']! as int,
        iconUrl: row['icon_url'] as String?,
        characterId: row['character_id'] as String?,
        characterName: row['character_name'] as String?,
        characterIconUrl: row['character_icon_url'] as String?,
        characterEmoji: row['character_emoji'] as String?,
        addedAt: row['added_at']! as int,
      );
}
