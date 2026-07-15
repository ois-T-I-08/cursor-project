import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/characters/apply_hoyolab_build_use_case.dart';
import '../application/characters/character_detail_state.dart';
import '../application/characters/load_character_detail_use_case.dart';
import '../application/characters/save_character_progress_use_case.dart';
import '../core/errors/user_facing_error.dart';
import '../data/artifact_score/artifact_score_resolver.dart';
import '../data/hoyolab/models/game_record.dart';
import '../domain/artifact_score.dart';
import '../domain/models/artifact_state.dart';
import '../domain/models/character_build_snapshot.dart';
import '../domain/models/master_models.dart';
import 'app_providers.dart';
import 'artifact_sets_page_providers.dart';
import 'hoyolab_game_providers.dart';
import 'growth_providers.dart';

final characterDetailProvider = AutoDisposeNotifierProvider.family<
    CharacterDetailNotifier, CharacterDetailState, String>(
  CharacterDetailNotifier.new,
);

class CharacterDetailNotifier
    extends AutoDisposeFamilyNotifier<CharacterDetailState, String> {
  static const _saveDebounceMs = 800;

  Timer? _saveTimer;
  bool _disposed = false;

  String get characterId => arg;

  @override
  CharacterDetailState build(String characterId) {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
    });
    Future.microtask(_load);
    return CharacterDetailState.initial();
  }

  Future<void> _load() async {
    try {
      final charRepo = await ref.read(characterRepositoryProvider.future);
      final progressRepo = await ref.read(progressRepositoryProvider.future);
      final userId = await ref.read(localUserIdProvider.future);
      final materials = await ref.read(materialsMapProvider.future);

      final loaded = await LoadCharacterDetailUseCase(
        characters: charRepo,
        progress: progressRepo,
      ).call(
        userId: userId,
        characterId: characterId,
        progressId: const Uuid().v4(),
        materials: materials,
        current: state,
      );

      if (_disposed) return;
      state = loaded;
      await _loadArtifactScoreSettings();
      if (_disposed) return;
      await _syncFromHoyolab();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        error: userFacingError(e),
        loading: false,
      );
      logAppError(e, null, 'characterDetail.load');
    }
  }

  Future<void> _loadWeaponUpgrade() async {
    final charRepo = await ref.read(characterRepositoryProvider.future);
    if (_disposed) return;
    state = await attachWeaponUpgrade(state, charRepo);
  }

  Future<void> _syncFromHoyolab() async {
    try {
      final build =
          await ref.read(hoyolabCharacterBuildProvider(characterId).future);
      if (build != null && build.isOwned) {
        await applyHoyolabBuild(build);
      }
    } catch (_) {
      // HoYoLAB 未連携・取得失敗時はローカル進捗のまま
    }
  }

  Future<void> applyHoyolabBuildSafe(HoyolabCharacterBuild build) async {
    try {
      await applyHoyolabBuild(build);
    } catch (_) {
      // HoYoLAB 反映失敗時も詳細画面は表示を継続
    }
  }

  Future<void> applyHoyolabBuild(HoyolabCharacterBuild build) async {
    if (_disposed) return;
    final charRepo = await ref.read(characterRepositoryProvider.future);
    final next = await ApplyHoyolabBuildUseCase(characters: charRepo).call(
      state: state,
      build: build,
    );
    if (_disposed || next == null) return;
    state = next;
    // debounce 破棄で聖遺物が進捗に残らないのを防ぐ（即保存）
    final progress = state.progress;
    if (progress != null) {
      await _persistProgress(progress);
    }
    ref.invalidate(artifactSetOverviewsProvider);
  }

  Future<void> resetToFetched() async {
    final snap = state.fetchedSnapshot;
    if (snap == null) return;

    state = state.copyWith(
      level: snap.level,
      constellation: snap.constellation.clamp(0, 6),
      talentNormal: snap.talentNormal,
      talentSkill: snap.talentSkill,
      talentBurst: snap.talentBurst,
      weaponId: snap.weaponId,
      weaponName: snap.weaponName,
      weaponRarity: snap.weaponRarity,
      weaponLevel: snap.weaponLevel,
      artifacts: copyArtifactState(snap.artifacts),
    );
    await _loadWeaponUpgrade();
    if (_disposed) return;
    _scheduleSave();
  }

  Future<void> _loadArtifactScoreSettings() async {
    final character = state.character;
    final progress = state.progress;
    if (character == null || progress == null) return;

    final userScoreType =
        userArtifactScoreTypeFromStorage(progress.artifactScoreType);
    final artifactScoreTypeUserSet = userScoreType != null;

    final resolver = ArtifactScoreResolver(
      ref.read(artifactScoreWeightRepositoryProvider),
    );
    final autoSettings = await resolver.resolve(character: character);
    final resolvedArtifactScoreType = autoSettings.scoreType;

    final settings = await resolver.resolve(
      character: character,
      userScoreType: userScoreType,
      userScoreTypeIsSet: artifactScoreTypeUserSet,
    );

    if (_disposed) return;
    state = state.copyWith(
      artifactScoreTypeUserSet: artifactScoreTypeUserSet,
      resolvedArtifactScoreType: resolvedArtifactScoreType,
      artifactScoreType: settings.scoreType,
      artifactScoreWeights: settings.weights,
    );
  }

  void _scheduleSave() {
    final base = state.progress;
    if (base == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: _saveDebounceMs),
      () => _persistProgress(base),
    );
  }

  Future<void> _persistProgress(UserProgress base) async {
    if (_disposed) return;
    try {
      final repo = await ref.read(progressRepositoryProvider.future);
      final mutation = await ref.read(progressMutationRepoProvider.future);
      final updated = await SaveCharacterProgressUseCase(
        progress: repo,
        mutation: mutation,
      ).call(
        base: base,
        state: state,
      );
      if (_disposed) return;
      state = state.copyWith(progress: updated);
      invalidateAfterProgressChange(ref, characterId: characterId);
      ref.invalidate(growthTimelineProvider);
    } catch (_) {
      // 保存失敗は UI を落とさない
    }
  }

  void updateLevel(int v) {
    state = state.copyWith(level: v);
    _scheduleSave();
  }

  void updateTargetLevel(int v) {
    state = state.copyWith(targetLevel: v);
  }

  void updateTalentNormal(int v) {
    state = state.copyWith(talentNormal: v);
    _scheduleSave();
  }

  void updateTalentSkill(int v) {
    state = state.copyWith(talentSkill: v);
    _scheduleSave();
  }

  void updateTalentBurst(int v) {
    state = state.copyWith(talentBurst: v);
    _scheduleSave();
  }

  void updateConstellation(int v) {
    state = state.copyWith(constellation: v.clamp(0, 6));
    _scheduleSave();
  }

  void updateWeaponLevel(int v) {
    state = state.copyWith(weaponLevel: v);
    _scheduleSave();
  }

  void updateTargetWeaponLevel(int v) {
    state = state.copyWith(targetWeaponLevel: v);
  }

  void updateArtifacts(ArtifactState artifacts) {
    state = state.copyWith(artifacts: artifacts);
    _scheduleSave();
    ref.invalidate(artifactSetOverviewsProvider);
  }

  void updateArtifactCompleted(bool completed) {
    state = state.copyWith(artifactCompleted: completed);
    _scheduleSave();
    ref.invalidate(artifactSetOverviewsProvider);
  }

  void updateArtifactScoreType(ArtifactScoreType type) {
    state = state.copyWith(
      artifactScoreType: type,
      artifactScoreWeights: scoreWeightsForType(type),
      artifactScoreTypeUserSet: true,
    );
    unawaited(_persistArtifactScoreType());
    _scheduleSave();
  }

  Future<void> _persistArtifactScoreType() async {
    final base = state.progress;
    if (base == null) return;

    final updated = base.copyWith(
      artifactScoreType: state.artifactScoreTypeUserSet
          ? artifactScoreTypeToUserStorage(state.artifactScoreType)
          : '',
    );
    state = state.copyWith(progress: updated);
    try {
      final repo = await ref.read(progressRepositoryProvider.future);
      await repo.save(updated);
      invalidateAfterProgressChange(ref, characterId: characterId);
    } catch (_) {
      // 保存失敗は UI を落とさない
    }
  }

  void clearWeapon() {
    state = state.copyWith(
      weaponId: '',
      weaponName: '',
      weaponPromotes: const [],
      weaponRarity: 4,
    );
    _scheduleSave();
  }

  Future<void> applyWeaponSelection(String weaponId) async {
    final newWeapon = state.weapons.where((x) => x.id == weaponId).firstOrNull;
    state = state.copyWith(
      weaponId: weaponId,
      weaponName: newWeapon?.name ?? '',
      weaponRarity: newWeapon?.rarity ?? 4,
    );
    await _loadWeaponUpgrade();
    if (_disposed) return;
    _scheduleSave();
  }

  CharacterBuildSnapshot snapshotFromCurrent() => state.snapshotFromCurrent();
}
