import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../models/master_models.dart';
import '../../../../domain/models/calculation_models.dart';
import '../app_database.dart';
import '../tables/master_tables.dart';
import '../../upgrade_serde.dart';

part 'character_dao.g.dart';

@DriftAccessor(tables: [Characters, Weapons, Materials, CharacterUpgrades, WeaponUpgrades])
class CharacterDao extends DatabaseAccessor<DriftAppDatabase>
    with _$CharacterDaoMixin {
  CharacterDao(super.db);

  Future<void> upsertCharacter(MasterCharacter c) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(characters).insertOnConflictUpdate(
      CharactersCompanion.insert(
        id: c.id,
        name: c.name,
        element: c.element,
        weaponType: c.weaponType,
        rarity: c.rarity,
        region: c.region,
        iconUrl: c.iconUrl,
        scoreType: Value(c.scoreType),
        syncedAt: now,
      ),
    );
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
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(weapons).insertOnConflictUpdate(
      WeaponsCompanion.insert(
        id: w.id,
        name: w.name,
        weaponType: w.weaponType,
        rarity: w.rarity,
        iconUrl: w.iconUrl,
        syncedAt: now,
      ),
    );
  }

  Future<MasterWeapon?> getWeapon(String id) async {
    final row = await (select(weapons)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _weaponFromRow(row);
  }

  Future<void> upsertMaterial(MasterMaterial m) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(materials).insertOnConflictUpdate(
      MaterialsCompanion.insert(
        id: m.id,
        name: m.name,
        category: m.category,
        rarity: Value(m.rarity),
        iconUrl: m.iconUrl,
        expValue: Value(m.expValue),
        expTarget: Value(m.expTarget),
        syncedAt: now,
      ),
    );
  }

  Future<List<MasterMaterial>> getAllMaterials() async {
    final rows = await (select(materials)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows.map(_materialFromRow).toList();
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
