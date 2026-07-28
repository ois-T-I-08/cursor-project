import '../../domain/models/master_models.dart';
import '../../domain/repositories/character_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import 'character_detail_state.dart';

/// キャラ詳細の初期読込（進捗・突破・武器一覧）。
class LoadCharacterDetailUseCase {
  const LoadCharacterDetailUseCase({
    required CharacterRepository characters,
    required ProgressRepository progress,
  }) : _characters = characters,
       _progress = progress;

  final CharacterRepository _characters;
  final ProgressRepository _progress;

  Future<CharacterDetailState> call({
    required String userId,
    required String characterId,
    required String progressId,
    required Map<String, MasterMaterial> materials,
    required CharacterDetailState current,
  }) async {
    final character = await _characters.getById(characterId);
    final upgrade = await _characters.getUpgrade(characterId);
    final promotes = upgrade?.promotes ?? [];
    final talents = upgrade?.talents ?? {};
    final weapons = await _characters.getAllWeapons();

    final progress = await _progress.getOrCreate(
      userId: userId,
      characterId: characterId,
      progressId: progressId,
    );

    var next = current.copyWith(
      character: character,
      promotes: promotes,
      talents: talents,
      weapons: weapons,
      materials: materials,
      progress: progress,
      weaponId: progress.weaponId,
      weaponName: progress.weaponName,
      weaponLevel: progress.weaponLevel,
      clearError: true,
    );

    next = await attachWeaponUpgrade(next, _characters);

    next = next.copyWith(
      level: progress.level,
      constellation: progress.constellation.clamp(0, 6),
      talentNormal: progress.talentNormal,
      talentSkill: progress.talentSkill,
      talentBurst: progress.talentBurst,
      artifacts: progress.artifacts,
      artifactCompleted: progress.artifactCompleted,
      loading: false,
      clearError: true,
    );
    return next.copyWith(fetchedSnapshot: next.snapshotFromCurrent());
  }
}

/// 装備武器の突破データ・レア度を state に付与する。
Future<CharacterDetailState> attachWeaponUpgrade(
  CharacterDetailState state,
  CharacterRepository characters,
) async {
  if (state.weaponId.isEmpty) {
    return state.copyWith(weaponPromotes: const [], weaponRarity: 4);
  }

  final weapon =
      state.weapons.where((w) => w.id == state.weaponId).firstOrNull ??
      await characters.getWeapon(state.weaponId);
  var weaponRarity = state.weaponRarity;
  var weaponName = state.weaponName;
  if (weapon != null) {
    weaponRarity = weapon.rarity;
    weaponName = weapon.name;
  }
  final weaponUpgrade = await characters.getWeaponUpgrade(state.weaponId);
  return state.copyWith(
    weaponRarity: weaponRarity,
    weaponName: weaponName,
    weaponPromotes: weaponUpgrade?.promotes ?? [],
  );
}
