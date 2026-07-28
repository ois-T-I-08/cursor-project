import '../../data/hoyolab/hoyolab_relic_sync.dart';
import '../../data/hoyolab/models/game_record.dart';
import '../../domain/hoyolab_slider_sync.dart';
import '../../domain/models/master_models.dart';
import '../../domain/repositories/character_repository.dart';
import 'character_detail_state.dart';
import 'load_character_detail_use_case.dart';

/// HoYoLAB ビルドを詳細 state へ反映する（純ロジック寄り）。
class ApplyHoyolabBuildUseCase {
  const ApplyHoyolabBuildUseCase({required CharacterRepository characters})
    : _characters = characters;

  final CharacterRepository _characters;

  Future<CharacterDetailState?> call({
    required CharacterDetailState state,
    required HoyolabCharacterBuild build,
  }) async {
    if (!build.isOwned) return null;

    final lastFetched = state.lastHoyolabFetchedAt;
    if (lastFetched != null &&
        build.fetchedAt != null &&
        !build.fetchedAt!.isAfter(lastFetched)) {
      return null;
    }

    final snapshot = buildHoyolabSliderSnapshot(
      level: build.level,
      promoteLevel: build.promoteLevel,
      constellation: build.constellation,
      talents:
          build.talents
              .map((t) => HoyolabTalentInput(name: t.name, level: t.level))
              .toList(),
      weaponId: build.weapon?.id,
      weaponName: build.weapon?.name,
      weaponLevel: build.weapon?.level,
      weaponRefinement: build.weapon?.refinement,
    );

    var next = state;
    if (snapshot.weaponId != null || snapshot.weaponName != null) {
      next = await _applyWeaponSnapshot(next, snapshot);
    }

    var artifacts = next.artifacts;
    if (build.relics.isNotEmpty) {
      artifacts = mergeRelicsFromHoyolab(
        local: artifacts,
        relics: build.relics,
      );
    }

    next = next.copyWith(
      level: snapshot.level,
      constellation: snapshot.constellation.clamp(0, 6),
      talentNormal: build.talents.isNotEmpty ? snapshot.talentNormal : null,
      talentSkill: build.talents.isNotEmpty ? snapshot.talentSkill : null,
      talentBurst: build.talents.isNotEmpty ? snapshot.talentBurst : null,
      artifacts: artifacts,
      hoyolabSynced: true,
      lastHoyolabFetchedAt: build.fetchedAt ?? DateTime.now(),
      progress: next.progress?.copyWith(
        level: snapshot.level,
        ascension: snapshot.promoteLevel,
        constellation: snapshot.constellation,
        talentNormal: build.talents.isNotEmpty ? snapshot.talentNormal : null,
        talentSkill: build.talents.isNotEmpty ? snapshot.talentSkill : null,
        talentBurst: build.talents.isNotEmpty ? snapshot.talentBurst : null,
        weaponId: next.weaponId,
        weaponName: next.weaponName,
        weaponLevel: next.weaponLevel,
        weaponRefinement:
            snapshot.weaponRefinement ?? next.progress?.weaponRefinement ?? 1,
        artifacts: artifacts,
      ),
    );
    return next.copyWith(fetchedSnapshot: next.snapshotFromCurrent());
  }

  Future<CharacterDetailState> _applyWeaponSnapshot(
    CharacterDetailState state,
    HoyolabSliderSnapshot snapshot,
  ) async {
    MasterWeapon? matched;
    if (snapshot.weaponId != null) {
      matched =
          state.weapons.where((w) => w.id == snapshot.weaponId).firstOrNull;
    }
    matched ??=
        snapshot.weaponName == null
            ? null
            : state.weapons
                .where((w) => w.name == snapshot.weaponName)
                .firstOrNull;

    var next = state;
    if (matched != null) {
      next = next.copyWith(
        weaponId: matched.id,
        weaponName: matched.name,
        weaponRarity: matched.rarity,
      );
    } else if (snapshot.weaponId != null) {
      next = next.copyWith(
        weaponId: snapshot.weaponId!,
        weaponName: snapshot.weaponName ?? '',
      );
    }
    if (snapshot.weaponLevel != null) {
      next = next.copyWith(weaponLevel: snapshot.weaponLevel!);
    }
    return attachWeaponUpgrade(next, _characters);
  }
}
