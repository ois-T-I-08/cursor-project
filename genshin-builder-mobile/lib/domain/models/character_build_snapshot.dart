import 'artifact_state.dart';

/// 取得データ（HoYoLAB / ローカル保存値）のスナップショット。
///
/// シミュレーション（スライダー等の編集状態）とは別に保持し、
/// 「取得情報に戻す」で編集状態をこの値に復元する。
/// 取得データそのものは変更しない（イミュータブル）。
class CharacterBuildSnapshot {
  const CharacterBuildSnapshot({
    required this.level,
    required this.constellation,
    required this.talentNormal,
    required this.talentSkill,
    required this.talentBurst,
    required this.weaponId,
    required this.weaponName,
    required this.weaponRarity,
    required this.weaponLevel,
    required this.artifacts,
  });

  final int level;

  /// 命ノ星座（0〜6）。将来の凸シミュレーション用に表示状態と分離して保持
  final int constellation;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final String weaponId;
  final String weaponName;
  final int weaponRarity;
  final int weaponLevel;
  final ArtifactState artifacts;

  CharacterBuildSnapshot copyWith({
    int? level,
    int? constellation,
    int? talentNormal,
    int? talentSkill,
    int? talentBurst,
    String? weaponId,
    String? weaponName,
    int? weaponRarity,
    int? weaponLevel,
    ArtifactState? artifacts,
  }) => CharacterBuildSnapshot(
    level: level ?? this.level,
    constellation: constellation ?? this.constellation,
    talentNormal: talentNormal ?? this.talentNormal,
    talentSkill: talentSkill ?? this.talentSkill,
    talentBurst: talentBurst ?? this.talentBurst,
    weaponId: weaponId ?? this.weaponId,
    weaponName: weaponName ?? this.weaponName,
    weaponRarity: weaponRarity ?? this.weaponRarity,
    weaponLevel: weaponLevel ?? this.weaponLevel,
    artifacts: artifacts ?? this.artifacts,
  );
}
