import '../../domain/models/calculation_models.dart';
import '../amber/amber_api.dart';
import '../db/app_database.dart';

class SyncResult {
  SyncResult({
    required this.provider,
    this.characters = 0,
    this.weapons = 0,
    this.materials = 0,
    this.characterUpgrades = 0,
    this.weaponUpgrades = 0,
    this.errors = const [],
  });

  final String provider;
  int characters;
  int weapons;
  int materials;
  int characterUpgrades;
  int weaponUpgrades;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'Sync($provider): chars=$characters weapons=$weapons materials=$materials '
      'charUp=$characterUpgrades wpnUp=$weaponUpgrades errors=${errors.length}';
}

/// マスターデータ同期（Web `sync.ts` 簡略版）
class MasterSyncService {
  MasterSyncService({
    required AmberApi amberApi,
    required AppDatabase db,
    this.syncUpgradeDetails = true,
    this.upgradeDetailLimit = 20,
  })  : _amber = amberApi,
        _db = db;

  final AmberApi _amber;
  final AppDatabase _db;
  final bool syncUpgradeDetails;
  final int upgradeDetailLimit;

  Future<SyncResult> syncMasterData() async {
    final result = SyncResult(provider: AmberApi.name);

    try {
      final characters = await _amber.fetchCharacters();
      await _db.upsertCharactersBatch(characters);
      result.characters = characters.length;
    } catch (e) {
      result.errors.add('characters: $e');
    }

    try {
      final weapons = await _amber.fetchWeapons();
      await _db.upsertWeaponsBatch(weapons);
      result.weapons = weapons.length;
    } catch (e) {
      result.errors.add('weapons: $e');
    }

    try {
      final materials = await _amber.fetchMaterials();
      await _db.upsertMaterialsBatch(materials);
      result.materials = materials.length;
    } catch (e) {
      result.errors.add('materials: $e');
    }

    if (syncUpgradeDetails) {
      await _syncCharacterUpgrades(result);
      await _syncWeaponUpgrades(result);
    }

    final status = result.hasErrors ? 'partial' : 'success';
    await _db.insertSyncLog(status, result.toString());

    return result;
  }

  Future<void> _syncCharacterUpgrades(SyncResult result) async {
    final characters = await _db.getAllCharacters();
    final targets = characters.take(upgradeDetailLimit);
    for (final c in targets) {
      try {
        final detail = await _amber.fetchAvatarDetail(c.id);
        final promotes = _parsePromotes(detail);
        final talents = _parseTalents(detail);
        await _db.upsertCharacterUpgrade(
          characterId: c.id,
          promotes: promotes,
          talents: talents,
        );
        result.characterUpgrades++;
      } catch (e) {
        result.errors.add('char upgrade ${c.id}: $e');
      }
    }
  }

  Future<void> _syncWeaponUpgrades(SyncResult result) async {
    // Phase 1: 詳細同期はキャラ優先。武器は将来拡張。
  }

  List<PromoteStage> _parsePromotes(Map<String, dynamic> detail) {
    final promotesRaw = detail['promote'] as List<dynamic>? ?? [];
    return promotesRaw.map((raw) {
      final p = raw as Map<String, dynamic>;
      final costItems = <String, int>{};
      final costs = p['costItems'] as List<dynamic>? ?? [];
      for (final item in costs) {
        final m = item as Map<String, dynamic>;
        final id = '${m['id']}';
        costItems[id] = (m['count'] as num?)?.toInt() ?? 0;
      }
      return PromoteStage(
        promoteLevel: (p['promoteLevel'] as num?)?.toInt() ?? 0,
        unlockMaxLevel: (p['unlockMaxLevel'] as num?)?.toInt() ?? 0,
        costItems: costItems,
        coinCost: (p['coinCost'] as num?)?.toInt() ?? 0,
        requiredPlayerLevel: (p['requiredPlayerLevel'] as num?)?.toInt(),
      );
    }).toList();
  }

  Map<String, List<TalentLevelUpgrade>> _parseTalents(
    Map<String, dynamic> detail,
  ) {
    final skills = detail['skills'] as List<dynamic>? ?? [];
    final result = <String, List<TalentLevelUpgrade>>{};
    for (var i = 0; i < skills.length; i++) {
      final skill = skills[i] as Map<String, dynamic>;
      final upgradesRaw = skill['upgrade'] as List<dynamic>? ?? [];
      result['skill_$i'] = upgradesRaw.map((raw) {
        final u = raw as Map<String, dynamic>;
        final costItems = <String, int>{};
        final costs = u['costItems'] as List<dynamic>? ?? [];
        for (final item in costs) {
          final m = item as Map<String, dynamic>;
          costItems['${m['id']}'] = (m['count'] as num?)?.toInt() ?? 0;
        }
        return TalentLevelUpgrade(
          level: (u['level'] as num?)?.toInt() ?? 0,
          costItems: costItems,
          coinCost: (u['coinCost'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }
    return result;
  }
}