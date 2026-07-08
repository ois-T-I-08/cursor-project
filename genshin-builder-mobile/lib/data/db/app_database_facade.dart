import '../../domain/models/bookmark.dart';
import '../../domain/models/calculation_models.dart';
import '../models/master_models.dart';
import '../models/sync_status.dart';
import 'drift/app_database.dart' hide LevelExpSegment;

/// Drift DAO への委譲ファサード（旧 sqflite [AppDatabase] と同一 API）
class AppDatabase {
  AppDatabase._(this._inner);

  final DriftAppDatabase _inner;

  static Future<AppDatabase> open() async {
    final inner = await DriftAppDatabase.open();
    return AppDatabase._(inner);
  }

  Future<void> close() => _inner.close();

  Future<void> upsertCharactersBatch(List<MasterCharacter> list) =>
      _inner.characterDao.upsertCharactersBatch(list);

  Future<void> upsertWeaponsBatch(List<MasterWeapon> list) =>
      _inner.characterDao.upsertWeaponsBatch(list);

  Future<void> upsertMaterialsBatch(List<MasterMaterial> list) =>
      _inner.characterDao.upsertMaterialsBatch(list);

  Future<void> upsertCharacter(MasterCharacter c) =>
      _inner.characterDao.upsertCharacter(c);

  Future<List<MasterCharacter>> getAllCharacters() =>
      _inner.characterDao.getAllCharacters();

  Future<MasterCharacter?> getCharacter(String id) =>
      _inner.characterDao.getCharacter(id);

  Future<void> upsertWeapon(MasterWeapon w) =>
      _inner.characterDao.upsertWeapon(w);

  Future<MasterWeapon?> getWeapon(String id) =>
      _inner.characterDao.getWeapon(id);

  Future<List<MasterWeapon>> getAllWeapons() =>
      _inner.characterDao.getAllWeapons();

  Future<void> upsertMaterial(MasterMaterial m) =>
      _inner.characterDao.upsertMaterial(m);

  Future<List<MasterMaterial>> getAllMaterials() =>
      _inner.characterDao.getAllMaterials();

  Future<MasterMaterial?> getMaterial(String id) =>
      _inner.characterDao.getMaterial(id);

  Future<Map<String, MasterMaterial>> getMaterialsMap() =>
      _inner.characterDao.getMaterialsMap();

  Future<void> upsertCharacterUpgrade({
    required String characterId,
    required List<PromoteStage> promotes,
    required Map<String, List<TalentLevelUpgrade>> talents,
  }) =>
      _inner.characterDao.upsertCharacterUpgrade(
        characterId: characterId,
        promotes: promotes,
        talents: talents,
      );

  Future<
      ({
        List<PromoteStage> promotes,
        Map<String, List<TalentLevelUpgrade>> talents,
      })?> getCharacterUpgrade(String characterId) =>
      _inner.characterDao.getCharacterUpgrade(characterId);

  Future<Set<String>> getSyncedCharacterUpgradeIds() =>
      _inner.characterDao.getSyncedCharacterUpgradeIds();

  Future<void> upsertWeaponUpgrade({
    required String weaponId,
    required List<PromoteStage> promotes,
    required List<String> levelUpItemIds,
  }) =>
      _inner.characterDao.upsertWeaponUpgrade(
        weaponId: weaponId,
        promotes: promotes,
        levelUpItemIds: levelUpItemIds,
      );

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
      getWeaponUpgrade(String weaponId) =>
          _inner.characterDao.getWeaponUpgrade(weaponId);

  Future<Set<String>> getSyncedWeaponUpgradeIds() =>
      _inner.characterDao.getSyncedWeaponUpgradeIds();

  Future<int> countExpMaterials() => _inner.characterDao.countExpMaterials();

  Future<void> updateMaterialExp({
    required String materialId,
    required int expValue,
    required String expTarget,
  }) =>
      _inner.characterDao.updateMaterialExp(
        materialId: materialId,
        expValue: expValue,
        expTarget: expTarget,
      );

  Future<int> countLevelExpSegments() =>
      _inner.characterDao.countLevelExpSegments();

  Future<void> upsertLevelExpSegments(List<LevelExpSegment> segments) =>
      _inner.characterDao.upsertLevelExpSegments(segments);

  List<LevelExpSegment> buildLevelExpSegments() =>
      _inner.characterDao.buildLevelExpSegments();

  Future<void> upsertProgress(UserProgress p) =>
      _inner.progressDao.upsertProgress(p);

  Future<UserProgress?> getProgress(String userId, String characterId) =>
      _inner.progressDao.getProgress(userId, characterId);

  Future<UserProgress> getOrCreateProgress(
    String userId,
    String characterId,
    String progressId,
  ) =>
      _inner.progressDao.getOrCreateProgress(userId, characterId, progressId);

  Future<List<MaterialBookmarkEntry>> getAllBookmarks() =>
      _inner.bookmarkDao.getAllBookmarks();

  Future<void> upsertBookmark(MaterialBookmarkEntry entry) =>
      _inner.bookmarkDao.upsertBookmark(entry);

  Future<void> removeBookmark(String id) =>
      _inner.bookmarkDao.removeBookmark(id);

  Future<void> removeBookmarksBySourceKey(String sourceKey) =>
      _inner.bookmarkDao.removeBookmarksBySourceKey(sourceKey);

  Future<void> removeBookmarksByMaterialId(String materialId) =>
      _inner.bookmarkDao.removeBookmarksByMaterialId(materialId);

  Future<void> clearAllBookmarks() => _inner.bookmarkDao.clearAllBookmarks();

  Future<void> insertSyncLog(String status, String detail) =>
      _inner.progressDao.insertSyncLog(status, detail);

  Future<String?> getSetting(String key) => _inner.progressDao.getSetting(key);

  Future<void> setSetting(String key, String value) =>
      _inner.progressDao.setSetting(key, value);

  Future<DateTime?> getLastSyncTime() => _inner.progressDao.getLastSyncTime();

  Future<SyncStatus> getSyncStatus() async {
    final characters = await _inner.characterDao.getAllCharacters();
    final weapons = await _inner.characterDao.getAllWeapons();
    final materials = await _inner.characterDao.getAllMaterials();
    final charUp = await _inner.characterDao.getSyncedCharacterUpgradeIds();
    final wpnUp = await _inner.characterDao.getSyncedWeaponUpgradeIds();
    final levelExp = await _inner.characterDao.countLevelExpSegments();
    final lastSync = await _inner.progressDao.getLastSyncTime();
    return SyncStatus(
      characters: characters.length,
      weapons: weapons.length,
      materials: materials.length,
      characterUpgrades: charUp.length,
      weaponUpgrades: wpnUp.length,
      levelExpSegments: levelExp,
      lastSyncedAt: lastSync,
    );
  }
}
