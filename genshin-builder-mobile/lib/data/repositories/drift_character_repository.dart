import '../../domain/models/calculation_models.dart';
import '../../domain/models/master_models.dart';
import '../../domain/repositories/character_repository.dart';
import '../db/app_database.dart';

class DriftCharacterRepository implements CharacterRepository {
  DriftCharacterRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<MasterCharacter>> getAll() => _db.getAllCharacters();

  @override
  Future<MasterCharacter?> getById(String id) => _db.getCharacter(id);

  @override
  Future<Map<String, MasterMaterial>> getMaterialsMap() =>
      _db.getMaterialsMap();

  @override
  Future<
    ({
      List<PromoteStage> promotes,
      Map<String, List<TalentLevelUpgrade>> talents,
    })?
  >
  getUpgrade(String characterId) => _db.getCharacterUpgrade(characterId);

  @override
  Future<
    Map<
      String,
      ({
        List<PromoteStage> promotes,
        Map<String, List<TalentLevelUpgrade>> talents,
      })
    >
  >
  getAllUpgrades() => _db.getAllCharacterUpgrades();

  @override
  Future<List<MasterWeapon>> getAllWeapons() => _db.getAllWeapons();

  @override
  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
  getWeaponUpgrade(String weaponId) => _db.getWeaponUpgrade(weaponId);

  @override
  Future<
    Map<String, ({List<PromoteStage> promotes, List<String> levelUpItemIds})>
  >
  getAllWeaponUpgrades() => _db.getAllWeaponUpgrades();

  @override
  Future<MasterWeapon?> getWeapon(String id) => _db.getWeapon(id);
}

/// 後方互換エイリアス
typedef CharacterRepositoryImpl = DriftCharacterRepository;
