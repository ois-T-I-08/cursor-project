import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../models/master_models.dart';
import '../../../../domain/level_config.dart';
import '../../../../domain/models/calculation_models.dart';
import '../../../config/level_exp_table_builder.dart';
import '../app_database.dart' hide LevelExpSegment;
import '../tables/master_tables.dart';
import '../../upgrade_serde.dart';
import '../../upgrade_content_hash.dart';

part 'character_dao.g.dart';

@DriftAccessor(tables: [
  Characters,
  Weapons,
  Materials,
  CharacterUpgrades,
  WeaponUpgrades,
  LevelExpSegments,
])
class CharacterDao extends DatabaseAccessor<DriftAppDatabase>
    with _$CharacterDaoMixin {
  CharacterDao(super.db);

  Future<void> upsertCharacter(MasterCharacter c) async {
    await into(characters)
        .insertOnConflictUpdate(_characterToCompanion(c));
  }

  Future<void> upsertCharactersBatch(List<MasterCharacter> list) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        characters,
        list.map(_characterToCompanion).toList(),
      );
    });
  }

  Future<void> upsertWeaponsBatch(List<MasterWeapon> list) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        weapons,
        list.map(_weaponToCompanion).toList(),
      );
    });
  }

  Future<void> upsertMaterialsBatch(List<MasterMaterial> list) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        materials,
        list.map(_materialToCompanion).toList(),
      );
    });
  }

  Future<List<MasterCharacter>> getAllCharacters() async {
    final rows = await (select(characters)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows.map(_characterFromRow).toList();
  }

  Future<MasterCharacter?> getCharacter(String id) async {
    final row = await (select(characters)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _characterFromRow(row);
  }

  Future<void> upsertWeapon(MasterWeapon w) async {
    await into(weapons).insertOnConflictUpdate(_weaponToCompanion(w));
  }

  Future<MasterWeapon?> getWeapon(String id) async {
    final row = await (select(weapons)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _weaponFromRow(row);
  }

  Future<List<MasterWeapon>> getAllWeapons() async {
    final rows = await (select(weapons)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map(_weaponFromRow).toList();
  }

  Future<void> upsertMaterial(MasterMaterial m) async {
    await into(materials).insertOnConflictUpdate(_materialToCompanion(m));
  }

  Future<List<MasterMaterial>> getAllMaterials() async {
    final rows = await (select(materials)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows.map(_materialFromRow).toList();
  }

  Future<MasterMaterial?> getMaterial(String id) async {
    final row = await (select(materials)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _materialFromRow(row);
  }

  Future<int> countExpMaterials() async {
    final query = selectOnly(materials)
      ..addColumns([materials.id.count()])
      ..where(
        materials.expValue.isNotNull() & materials.expTarget.isNotNull(),
      );
    final row = await query.getSingle();
    return row.read(materials.id.count()) ?? 0;
  }

  Future<void> updateMaterialExp({
    required String materialId,
    required int expValue,
    required String expTarget,
  }) async {
    await (update(materials)..where((t) => t.id.equals(materialId))).write(
      MaterialsCompanion(
        expValue: Value(expValue),
        expTarget: Value(expTarget),
        syncedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<int> countLevelExpSegments() async {
    final query = selectOnly(levelExpSegments)
      ..addColumns([levelExpSegments.id.count()]);
    final row = await query.getSingle();
    return row.read(levelExpSegments.id.count()) ?? 0;
  }

  Future<void> upsertLevelExpSegments(List<LevelExpSegment> segments) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        levelExpSegments,
        segments
            .map(
              (s) => LevelExpSegmentsCompanion.insert(
                id: s.id,
                targetType: s.targetType,
                rarity: Value(s.rarity),
                fromLevel: s.fromLevel,
                toLevel: s.toLevel,
                expRequired: s.expRequired,
                moraRequired: Value(s.moraRequired),
                syncedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .toList(),
      );
    });
  }

  Future<List<LevelExpSegment>> getAllLevelExpSegments() async {
    final rows = await select(levelExpSegments).get();
    return rows
        .map(
          (r) => LevelExpSegment(
            id: r.id,
            targetType: r.targetType,
            rarity: r.rarity,
            fromLevel: r.fromLevel,
            toLevel: r.toLevel,
            expRequired: r.expRequired,
            moraRequired: r.moraRequired,
          ),
        )
        .toList();
  }

  /// `assets/config/level_exp_table.json` 相当の組み込み表からセグメントを構築。
  /// 同期時は [LevelExpTableSource] 経由で asset を読むのが正本。
  List<LevelExpSegment> buildLevelExpSegments() =>
      LevelExpTableBuilder.buildFromMaps(
        characterExp: characterExpBetweenMarks,
        weaponExpByRarity: LevelExpTableBuilder.defaultWeaponExpByRarity,
        marks: levelMarks,
      );

  Future<Map<String, MasterMaterial>> getMaterialsMap() async {
    final all = await getAllMaterials();
    return {for (final m in all) m.id: m};
  }

  Future<void> upsertCharacterUpgrade({
    required String characterId,
    required List<PromoteStage> promotes,
    required Map<String, List<TalentLevelUpgrade>> talents,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final promotesJson =
        jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList());
    final talentsJson = jsonEncode(
      talents.map(
        (key, value) =>
            MapEntry(key, value.map(UpgradeSerde.talentToJson).toList()),
      ),
    );
    final hash = computeUpgradeContentHash(
      promotesJson: promotesJson,
      secondaryJson: talentsJson,
    );
    await into(characterUpgrades).insertOnConflictUpdate(
      CharacterUpgradesCompanion.insert(
        characterId: characterId,
        promotes: promotesJson,
        talents: talentsJson,
        contentHash: Value(hash),
        syncedAt: now,
      ),
    );
  }

  Future<
      ({
        List<PromoteStage> promotes,
        Map<String, List<TalentLevelUpgrade>> talents,
      })?> getCharacterUpgrade(String characterId) async {
    final row = await (select(characterUpgrades)
          ..where((t) => t.characterId.equals(characterId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _parseCharacterUpgradeRow(row);
  }

  Future<
      Map<
          String,
          ({
            List<PromoteStage> promotes,
            Map<String, List<TalentLevelUpgrade>> talents,
          })>> getAllCharacterUpgrades() async {
    final rows = await select(characterUpgrades).get();
    final result = <String, ({
      List<PromoteStage> promotes,
      Map<String, List<TalentLevelUpgrade>> talents,
    })>{};
    for (final row in rows) {
      final parsed = _parseCharacterUpgradeRow(row);
      if (parsed != null) result[row.characterId] = parsed;
    }
    return result;
  }

  ({
    List<PromoteStage> promotes,
    Map<String, List<TalentLevelUpgrade>> talents,
  })? _parseCharacterUpgradeRow(CharacterUpgrade row) {
    try {
      final promotesRaw = jsonDecode(row.promotes) as List;
      final talentsRaw = jsonDecode(row.talents) as Map<String, dynamic>;
      return (
        promotes: promotesRaw
            .map((e) => UpgradeSerde.promoteFromJson(e as Map<String, dynamic>))
            .toList(),
        talents: talentsRaw.map(
          (key, value) => MapEntry(
            key,
            (value as List)
                .map((e) => UpgradeSerde.talentFromJson(
                      e as Map<String, dynamic>,
                    ))
                .toList(),
          ),
        ),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 同期済みキャラ upgrade の ID 一覧（差分同期用）
  Future<Set<String>> getSyncedCharacterUpgradeIds() async {
    final query = selectOnly(characterUpgrades)
      ..addColumns([characterUpgrades.characterId]);
    final rows = await query.get();
    return rows
        .map((r) => r.read(characterUpgrades.characterId))
        .whereType<String>()
        .toSet();
  }

  /// characterId → contentHash（空文字は未ハッシュ / マイグレーション直後）
  Future<Map<String, String>> getCharacterUpgradeHashes() async {
    final query = selectOnly(characterUpgrades)
      ..addColumns([
        characterUpgrades.characterId,
        characterUpgrades.contentHash,
      ]);
    final rows = await query.get();
    final map = <String, String>{};
    for (final row in rows) {
      final id = row.read(characterUpgrades.characterId);
      if (id == null) continue;
      map[id] = row.read(characterUpgrades.contentHash) ?? '';
    }
    return map;
  }

  Future<void> upsertWeaponUpgrade({
    required String weaponId,
    required List<PromoteStage> promotes,
    required List<String> levelUpItemIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final promotesJson =
        jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList());
    final itemsJson = jsonEncode(levelUpItemIds);
    final hash = computeUpgradeContentHash(
      promotesJson: promotesJson,
      secondaryJson: itemsJson,
    );
    await into(weaponUpgrades).insertOnConflictUpdate(
      WeaponUpgradesCompanion.insert(
        weaponId: weaponId,
        promotes: promotesJson,
        levelUpItemIds: Value(itemsJson),
        contentHash: Value(hash),
        syncedAt: now,
      ),
    );
  }

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
      getWeaponUpgrade(String weaponId) async {
    final row = await (select(weaponUpgrades)
          ..where((t) => t.weaponId.equals(weaponId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _parseWeaponUpgradeRow(row);
  }

  Future<
      Map<
          String,
          ({
            List<PromoteStage> promotes,
            List<String> levelUpItemIds,
          })>> getAllWeaponUpgrades() async {
    final rows = await select(weaponUpgrades).get();
    final result = <String, ({
      List<PromoteStage> promotes,
      List<String> levelUpItemIds,
    })>{};
    for (final row in rows) {
      final parsed = _parseWeaponUpgradeRow(row);
      if (parsed != null) result[row.weaponId] = parsed;
    }
    return result;
  }

  ({List<PromoteStage> promotes, List<String> levelUpItemIds})?
      _parseWeaponUpgradeRow(WeaponUpgrade row) {
    try {
      final promotesRaw = jsonDecode(row.promotes) as List;
      final itemIds =
          (jsonDecode(row.levelUpItemIds) as List).cast<String>();
      return (
        promotes: promotesRaw
            .map((e) => UpgradeSerde.promoteFromJson(e as Map<String, dynamic>))
            .toList(),
        levelUpItemIds: itemIds,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 同期済み武器 upgrade の ID 一覧（差分同期用）
  Future<Set<String>> getSyncedWeaponUpgradeIds() async {
    final query = selectOnly(weaponUpgrades)
      ..addColumns([weaponUpgrades.weaponId]);
    final rows = await query.get();
    return rows
        .map((r) => r.read(weaponUpgrades.weaponId))
        .whereType<String>()
        .toSet();
  }

  /// weaponId → contentHash
  Future<Map<String, String>> getWeaponUpgradeHashes() async {
    final query = selectOnly(weaponUpgrades)
      ..addColumns([weaponUpgrades.weaponId, weaponUpgrades.contentHash]);
    final rows = await query.get();
    final map = <String, String>{};
    for (final row in rows) {
      final id = row.read(weaponUpgrades.weaponId);
      if (id == null) continue;
      map[id] = row.read(weaponUpgrades.contentHash) ?? '';
    }
    return map;
  }

  CharactersCompanion _characterToCompanion(MasterCharacter c) =>
      CharactersCompanion.insert(
        id: c.id,
        name: c.name,
        element: c.element,
        weaponType: c.weaponType,
        rarity: c.rarity,
        region: c.region,
        iconUrl: c.iconUrl,
        scoreType: Value(c.scoreType),
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      );

  WeaponsCompanion _weaponToCompanion(MasterWeapon w) =>
      WeaponsCompanion.insert(
        id: w.id,
        name: w.name,
        weaponType: w.weaponType,
        rarity: w.rarity,
        iconUrl: w.iconUrl,
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      );

  MaterialsCompanion _materialToCompanion(MasterMaterial m) =>
      MaterialsCompanion.insert(
        id: m.id,
        name: m.name,
        category: m.category,
        rarity: Value(m.rarity),
        iconUrl: m.iconUrl,
        expValue: Value(m.expValue),
        expTarget: Value(m.expTarget),
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      );

  MasterCharacter _characterFromRow(Character row) => MasterCharacter(
        id: row.id,
        name: row.name,
        element: row.element,
        weaponType: row.weaponType,
        rarity: row.rarity,
        region: row.region,
        iconUrl: row.iconUrl,
        scoreType: row.scoreType,
      );

  MasterWeapon _weaponFromRow(Weapon row) => MasterWeapon(
        id: row.id,
        name: row.name,
        weaponType: row.weaponType,
        rarity: row.rarity,
        iconUrl: row.iconUrl,
      );

  MasterMaterial _materialFromRow(Material row) => MasterMaterial(
        id: row.id,
        name: row.name,
        category: row.category,
        rarity: row.rarity,
        iconUrl: row.iconUrl,
        expValue: row.expValue,
        expTarget: row.expTarget,
      );
}
