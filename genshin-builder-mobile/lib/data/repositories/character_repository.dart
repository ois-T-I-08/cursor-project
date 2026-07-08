import '../../domain/models/calculation_models.dart';
import '../db/app_database.dart';
import '../models/master_models.dart';

class CharacterRepository {
  CharacterRepository(this._db);

  final AppDatabase _db;

  Future<List<MasterCharacter>> getAll() => _db.getAllCharacters();

  Future<MasterCharacter?> getById(String id) => _db.getCharacter(id);

  Future<Map<String, MasterMaterial>> getMaterialsMap() =>
      _db.getMaterialsMap();

  Future<
      ({
        List<PromoteStage> promotes,
        Map<String, List<TalentLevelUpgrade>> talents,
      })?> getUpgrade(String characterId) =>
      _db.getCharacterUpgrade(characterId);

  Future<List<MasterWeapon>> getAllWeapons() => _db.getAllWeapons();

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
      getWeaponUpgrade(String weaponId) => _db.getWeaponUpgrade(weaponId);

  Future<MasterWeapon?> getWeapon(String id) => _db.getWeapon(id);
}
