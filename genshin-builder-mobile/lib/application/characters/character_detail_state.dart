import '../../domain/artifact_score.dart';
import '../../domain/artifact_score_weights.dart';
import '../../domain/level_config.dart';
import '../../domain/models/artifact_state.dart';
import '../../domain/models/calculation_models.dart';
import '../../domain/models/character_build_snapshot.dart';
import '../../domain/models/master_models.dart';

/// キャラ詳細の編集・読込状態（イミュータブル）。features 非依存。
class CharacterDetailState {
  const CharacterDetailState({
    this.loading = true,
    this.error,
    this.fetchedSnapshot,
    this.level = 1,
    this.targetLevel = levelMax,
    this.constellation = 0,
    this.talentNormal = 1,
    this.talentSkill = 1,
    this.talentBurst = 1,
    this.weaponLevel = 1,
    this.targetWeaponLevel = levelMax,
    this.weaponId = '',
    this.weaponName = '',
    this.weaponRarity = 4,
    required this.artifacts,
    this.character,
    this.progress,
    this.weapons = const [],
    this.promotes = const [],
    this.weaponPromotes = const [],
    this.talents = const {},
    this.materials = const {},
    this.hoyolabSynced = false,
    this.lastHoyolabFetchedAt,
    this.artifactScoreType = ArtifactScoreType.atk,
    this.resolvedArtifactScoreType = ArtifactScoreType.atk,
    required this.artifactScoreWeights,
    this.artifactScoreTypeUserSet = false,
    this.artifactCompleted = false,
  });

  factory CharacterDetailState.initial() => CharacterDetailState(
    artifacts: createEmptyArtifactState(),
    artifactScoreWeights: scoreWeightsForType(ArtifactScoreType.atk),
  );

  final bool loading;
  final String? error;
  final CharacterBuildSnapshot? fetchedSnapshot;
  final int level;
  final int targetLevel;
  final int constellation;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final int weaponLevel;
  final int targetWeaponLevel;
  final String weaponId;
  final String weaponName;
  final int weaponRarity;
  final ArtifactState artifacts;
  final MasterCharacter? character;
  final UserProgress? progress;
  final List<MasterWeapon> weapons;
  final List<PromoteStage> promotes;
  final List<PromoteStage> weaponPromotes;
  final Map<String, List<TalentLevelUpgrade>> talents;
  final Map<String, MasterMaterial> materials;
  final bool hoyolabSynced;
  final DateTime? lastHoyolabFetchedAt;
  final ArtifactScoreType artifactScoreType;
  final ArtifactScoreType resolvedArtifactScoreType;
  final ArtifactStatWeights artifactScoreWeights;
  final bool artifactScoreTypeUserSet;

  /// 聖遺物育成完了チェック（ユーザー手動）
  final bool artifactCompleted;

  CharacterBuildSnapshot snapshotFromCurrent() => CharacterBuildSnapshot(
    level: level,
    constellation: constellation,
    talentNormal: talentNormal,
    talentSkill: talentSkill,
    talentBurst: talentBurst,
    weaponId: weaponId,
    weaponName: weaponName,
    weaponRarity: weaponRarity,
    weaponLevel: weaponLevel,
    artifacts: copyArtifactState(artifacts),
  );

  CharacterDetailState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    CharacterBuildSnapshot? fetchedSnapshot,
    int? level,
    int? targetLevel,
    int? constellation,
    int? talentNormal,
    int? talentSkill,
    int? talentBurst,
    int? weaponLevel,
    int? targetWeaponLevel,
    String? weaponId,
    String? weaponName,
    int? weaponRarity,
    ArtifactState? artifacts,
    MasterCharacter? character,
    UserProgress? progress,
    List<MasterWeapon>? weapons,
    List<PromoteStage>? promotes,
    List<PromoteStage>? weaponPromotes,
    Map<String, List<TalentLevelUpgrade>>? talents,
    Map<String, MasterMaterial>? materials,
    bool? hoyolabSynced,
    DateTime? lastHoyolabFetchedAt,
    ArtifactScoreType? artifactScoreType,
    ArtifactScoreType? resolvedArtifactScoreType,
    ArtifactStatWeights? artifactScoreWeights,
    bool? artifactScoreTypeUserSet,
    bool? artifactCompleted,
  }) => CharacterDetailState(
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    fetchedSnapshot: fetchedSnapshot ?? this.fetchedSnapshot,
    level: level ?? this.level,
    targetLevel: targetLevel ?? this.targetLevel,
    constellation: constellation ?? this.constellation,
    talentNormal: talentNormal ?? this.talentNormal,
    talentSkill: talentSkill ?? this.talentSkill,
    talentBurst: talentBurst ?? this.talentBurst,
    weaponLevel: weaponLevel ?? this.weaponLevel,
    targetWeaponLevel: targetWeaponLevel ?? this.targetWeaponLevel,
    weaponId: weaponId ?? this.weaponId,
    weaponName: weaponName ?? this.weaponName,
    weaponRarity: weaponRarity ?? this.weaponRarity,
    artifacts: artifacts ?? this.artifacts,
    character: character ?? this.character,
    progress: progress ?? this.progress,
    weapons: weapons ?? this.weapons,
    promotes: promotes ?? this.promotes,
    weaponPromotes: weaponPromotes ?? this.weaponPromotes,
    talents: talents ?? this.talents,
    materials: materials ?? this.materials,
    hoyolabSynced: hoyolabSynced ?? this.hoyolabSynced,
    lastHoyolabFetchedAt: lastHoyolabFetchedAt ?? this.lastHoyolabFetchedAt,
    artifactScoreType: artifactScoreType ?? this.artifactScoreType,
    resolvedArtifactScoreType:
        resolvedArtifactScoreType ?? this.resolvedArtifactScoreType,
    artifactScoreWeights: artifactScoreWeights ?? this.artifactScoreWeights,
    artifactScoreTypeUserSet:
        artifactScoreTypeUserSet ?? this.artifactScoreTypeUserSet,
    artifactCompleted: artifactCompleted ?? this.artifactCompleted,
  );
}
