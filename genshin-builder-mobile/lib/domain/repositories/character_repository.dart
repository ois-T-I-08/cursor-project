import '../models/calculation_models.dart';
import '../models/master_models.dart';

/// キャラ・武器マスタと突破データの読み取り契約。
abstract class CharacterRepository {
  Future<List<MasterCharacter>> getAll();

  Future<MasterCharacter?> getById(String id);

  Future<Map<String, MasterMaterial>> getMaterialsMap();

  Future<
    ({
      List<PromoteStage> promotes,
      Map<String, List<TalentLevelUpgrade>> talents,
    })?
  >
  getUpgrade(String characterId);

  Future<
    Map<
      String,
      ({
        List<PromoteStage> promotes,
        Map<String, List<TalentLevelUpgrade>> talents,
      })
    >
  >
  getAllUpgrades();

  Future<List<MasterWeapon>> getAllWeapons();

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
  getWeaponUpgrade(String weaponId);

  Future<
    Map<String, ({List<PromoteStage> promotes, List<String> levelUpItemIds})>
  >
  getAllWeaponUpgrades();

  Future<MasterWeapon?> getWeapon(String id);
}
