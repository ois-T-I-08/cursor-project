import '../repositories/bookmark_repository.dart';
import '../repositories/character_repository.dart';
import '../repositories/progress_repository.dart';
import '../../domain/daily_materials/daily_material_models.dart';
import '../../domain/daily_materials/daily_material_planner.dart';
import '../../domain/models/bookmark.dart';
import 'daily_material_schedule_repository.dart';

/// 曜日素材画面用の集計サービス（UI から DB/計算を隔離）
class DailyMaterialsService {
  DailyMaterialsService({
    required DailyMaterialScheduleRepository scheduleRepository,
    required CharacterRepository characterRepository,
    required ProgressRepository progressRepository,
    required BookmarkRepository bookmarkRepository,
  })  : _scheduleRepository = scheduleRepository,
        _characterRepository = characterRepository,
        _progressRepository = progressRepository,
        _bookmarkRepository = bookmarkRepository;

  final DailyMaterialScheduleRepository _scheduleRepository;
  final CharacterRepository _characterRepository;
  final ProgressRepository _progressRepository;
  final BookmarkRepository _bookmarkRepository;

  Future<DailyMaterialsPlan> buildPlan({
    required String userId,
    required int weekday,
    Set<String> ownedCharacterIds = const {},
  }) async {
    final schedule = await _scheduleRepository.getSchedule();
    final materials = await _characterRepository.getMaterialsMap();
    final characters = await _characterRepository.getAll();
    final weapons = await _characterRepository.getAllWeapons();
    final characterUpgrades = await _characterRepository.getAllUpgrades();
    final weaponUpgrades = await _characterRepository.getAllWeaponUpgrades();
    final progressList = await _progressRepository.getAll(userId);
    final bookmarks = await _bookmarkRepository.getAll();

    final progressByCharacter = {
      for (final p in progressList) p.characterId: p,
    };
    final characterById = {for (final c in characters) c.id: c};

    final buildingCharacterIds = <String>{};
    final buildingWeaponIds = <String>{};
    for (final b in bookmarks) {
      final characterId = b.characterId;
      if (characterId != null && characterId.isNotEmpty) {
        buildingCharacterIds.add(characterId);
      }
      _collectBuildingWeaponId(b, buildingWeaponIds);
    }

    // weaponId → 装備キャラ
    final equippedByWeapon = <String, List<DailyEquippedCharacter>>{};
    final weaponLevelById = <String, int>{};
    final weaponRefinementById = <String, int>{};
    for (final p in progressList) {
      if (p.weaponId.isEmpty) continue;
      final character = characterById[p.characterId];
      equippedByWeapon.putIfAbsent(p.weaponId, () => []).add(
            DailyEquippedCharacter(
              id: p.characterId,
              name: character?.name ?? p.characterId,
              iconUrl: character?.iconUrl,
            ),
          );
      final prevLv = weaponLevelById[p.weaponId];
      if (prevLv == null || p.weaponLevel < prevLv) {
        weaponLevelById[p.weaponId] = p.weaponLevel;
      }
      final prevRef = weaponRefinementById[p.weaponId];
      if (prevRef == null || p.weaponRefinement > prevRef) {
        weaponRefinementById[p.weaponId] = p.weaponRefinement;
      }
    }

    final talentEntries = <CharacterTalentCatalogEntry>[];
    for (final character in characters) {
      final upgrade = characterUpgrades[character.id];
      if (upgrade == null) continue;
      final materialIds = materialIdsFromTalents(upgrade.talents);
      if (materialIds.isEmpty) continue;
      talentEntries.add(
        CharacterTalentCatalogEntry(
          character: character,
          talentMaterialIds: materialIds,
          progress: progressByCharacter[character.id],
          talents: upgrade.talents,
          isOwned: ownedCharacterIds.contains(character.id),
          isBuilding: buildingCharacterIds.contains(character.id),
        ),
      );
    }

    final weaponEntries = <WeaponAscensionCatalogEntry>[];
    for (final weapon in weapons) {
      final upgrade = weaponUpgrades[weapon.id];
      if (upgrade == null) continue;
      final materialIds = materialIdsFromPromotes(upgrade.promotes);
      if (materialIds.isEmpty) continue;
      final equipped = equippedByWeapon[weapon.id] ?? const [];
      weaponEntries.add(
        WeaponAscensionCatalogEntry(
          weapon: weapon,
          ascensionMaterialIds: materialIds,
          weaponLevel: weaponLevelById[weapon.id],
          weaponRefinement: weaponRefinementById[weapon.id],
          promotes: upgrade.promotes,
          equippedCharacters: equipped,
          isOwned: equipped.isNotEmpty,
          isBuilding: buildingWeaponIds.contains(weapon.id),
        ),
      );
    }

    return buildDailyMaterialsPlan(
      schedule: schedule,
      weekday: weekday,
      materials: materials,
      characters: talentEntries,
      weapons: weaponEntries,
    );
  }

  void _collectBuildingWeaponId(
    MaterialBookmarkEntry bookmark,
    Set<String> out,
  ) {
    final key = bookmark.sourceKey;
    // range:weapon-level:{weaponId}:... / item:weapon-level:{weaponId}:...
    final parts = key.split(':');
    if (parts.length < 3) return;
    if (parts[1] != 'weapon-level') return;
    final weaponId = parts[2];
    if (weaponId.isNotEmpty) out.add(weaponId);
  }
}
