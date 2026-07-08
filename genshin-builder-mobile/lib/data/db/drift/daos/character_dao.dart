import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../models/master_models.dart';
import '../../../../domain/level_config.dart';
import '../../../../domain/models/calculation_models.dart';
import '../app_database.dart' hide LevelExpSegment;
import '../tables/master_tables.dart';
import '../../upgrade_serde.dart';

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

  /// Web `buildLevelExpSegments` 相当の定数データ
  List<LevelExpSegment> buildLevelExpSegments() {
    const characterExp = <String, int>{
      '1-20': 12275,
      '20-30': 57900,
      '30-40': 65700,
      '40-50': 39300,
      '50-60': 94800,
      '60-70': 114300,
      '70-80': 280800,
      '80-90': 393750,
    };

    const weaponExpByRarity = <int, Map<String, int>>{
      3: {
        '1-20': 53475,
        '20-30': 127978,
        '30-40': 145247,
        '40-50': 275350,
        '50-60': 408650,
        '60-70': 572725,
        '70-80': 772825,
        '80-90': 1638650,
      },
      4: {
        '1-20': 81000,
        '20-30': 194512,
        '30-40': 220613,
        '40-50': 418725,
        '50-60': 618400,
        '60-70': 866675,
        '70-80': 1168350,
        '80-90': 2476475,
      },
      5: {
        '1-20': 121550,
        '20-30': 291591,
        '30-40': 331209,
        '40-50': 628150,
        '50-60': 927675,
        '60-70': 1299125,
        '70-80': 1750375,
        '80-90': 3714775,
      },
    };

    final segments = <LevelExpSegment>[];
    for (var i = 0; i < levelMarks.length - 1; i++) {
      final from = levelMarks[i];
      final to = levelMarks[i + 1];
      final key = '$from-$to';
      final charExp = characterExp[key] ?? 0;
      segments.add(
        LevelExpSegment(
          id: 'character-0-$from-$to',
          targetType: 'character',
          rarity: 0,
          fromLevel: from,
          toLevel: to,
          expRequired: charExp,
          moraRequired: (charExp / 10).round(),
        ),
      );

      for (final rarity in [3, 4, 5]) {
        final exp = weaponExpByRarity[rarity]?[key] ?? 0;
        segments.add(
          LevelExpSegment(
            id: 'weapon-$rarity-$from-$to',
            targetType: 'weapon',
            rarity: rarity,
            fromLevel: from,
            toLevel: to,
            expRequired: exp,
            moraRequired: (exp / 10).round(),
          ),
        );
      }
    }
    return segments;
  }

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
    await into(characterUpgrades).insertOnConflictUpdate(
      CharacterUpgradesCompanion.insert(
        characterId: characterId,
        promotes: jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList()),
        talents: jsonEncode(
          talents.map(
            (key, value) =>
                MapEntry(key, value.map(UpgradeSerde.talentToJson).toList()),
          ),
        ),
        syncedAt: now,
      ),
    );
  }

  Future<({
    List<PromoteStage> promotes,
    Map<String, List<TalentLevelUpgrade>> talents,
  })?> getCharacterUpgrade(String characterId) async {
    final row = await (select(characterUpgrades)
          ..where((t) => t.characterId.equals(characterId)))
        .getSingleOrNull();
    if (row == null) return null;
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
              .map((e) => UpgradeSerde.talentFromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      ),
    );
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

  Future<void> upsertWeaponUpgrade({
    required String weaponId,
    required List<PromoteStage> promotes,
    required List<String> levelUpItemIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(weaponUpgrades).insertOnConflictUpdate(
      WeaponUpgradesCompanion.insert(
        weaponId: weaponId,
        promotes: jsonEncode(promotes.map(UpgradeSerde.promoteToJson).toList()),
        levelUpItemIds: Value(jsonEncode(levelUpItemIds)),
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
    final promotesRaw = jsonDecode(row.promotes) as List;
    final itemIds =
        (jsonDecode(row.levelUpItemIds) as List).cast<String>();
    return (
      promotes: promotesRaw
          .map((e) => UpgradeSerde.promoteFromJson(e as Map<String, dynamic>))
          .toList(),
      levelUpItemIds: itemIds,
    );
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
