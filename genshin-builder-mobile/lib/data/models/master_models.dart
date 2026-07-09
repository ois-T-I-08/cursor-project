import '../../domain/models/artifact_state.dart';

class MasterCharacter {
  const MasterCharacter({
    required this.id,
    required this.name,
    required this.element,
    required this.weaponType,
    required this.rarity,
    required this.region,
    required this.iconUrl,
    this.scoreType = 'atk',
  });

  final String id;
  final String name;
  final String element;
  final String weaponType;
  final int rarity;
  final String region;
  final String iconUrl;
  final String scoreType;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'element': element,
        'weapon_type': weaponType,
        'rarity': rarity,
        'region': region,
        'icon_url': iconUrl,
        'score_type': scoreType,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory MasterCharacter.fromMap(Map<String, Object?> map) => MasterCharacter(
        id: map['id'] as String,
        name: map['name'] as String,
        element: map['element'] as String,
        weaponType: map['weapon_type'] as String,
        rarity: map['rarity'] as int,
        region: map['region'] as String,
        iconUrl: map['icon_url'] as String,
        scoreType: map['score_type'] as String? ?? 'atk',
      );
}

class MasterWeapon {
  const MasterWeapon({
    required this.id,
    required this.name,
    required this.weaponType,
    required this.rarity,
    required this.iconUrl,
  });

  final String id;
  final String name;
  final String weaponType;
  final int rarity;
  final String iconUrl;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'weapon_type': weaponType,
        'rarity': rarity,
        'icon_url': iconUrl,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory MasterWeapon.fromMap(Map<String, Object?> map) => MasterWeapon(
        id: map['id'] as String,
        name: map['name'] as String,
        weaponType: map['weapon_type'] as String,
        rarity: map['rarity'] as int,
        iconUrl: map['icon_url'] as String,
      );
}

class MasterMaterial {
  const MasterMaterial({
    required this.id,
    required this.name,
    required this.category,
    this.rarity,
    required this.iconUrl,
    this.expValue,
    this.expTarget,
  });

  final String id;
  final String name;
  final String category;
  final int? rarity;
  final String iconUrl;
  final int? expValue;
  final String? expTarget;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'rarity': rarity,
        'icon_url': iconUrl,
        'exp_value': expValue,
        'exp_target': expTarget,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory MasterMaterial.fromMap(Map<String, Object?> map) => MasterMaterial(
        id: map['id'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        rarity: map['rarity'] as int?,
        iconUrl: map['icon_url'] as String,
        expValue: map['exp_value'] as int?,
        expTarget: map['exp_target'] as String?,
      );
}

class UserProgress {
  const UserProgress({
    required this.id,
    required this.userId,
    required this.characterId,
    this.level = 1,
    this.ascension = 0,
    this.constellation = 0,
    this.talentNormal = 1,
    this.talentSkill = 1,
    this.talentBurst = 1,
    this.weaponId = '',
    this.weaponName = '',
    this.weaponLevel = 1,
    this.weaponRefinement = 1,
    this.artifactsJson = '{}',
    this.isCompleted = false,
    this.memo = '',
    this.artifactScoreType = '',
  });

  final String id;
  final String userId;
  final String characterId;
  final int level;
  final int ascension;
  final int constellation;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final String weaponId;
  final String weaponName;
  final int weaponLevel;
  final int weaponRefinement;
  final String artifactsJson;
  final bool isCompleted;
  final String memo;
  final String artifactScoreType;

  ArtifactState get artifacts => parseArtifactState(artifactsJson);

  Map<String, Object?> toMap() => {
        'id': id,
        'user_id': userId,
        'character_id': characterId,
        'level': level,
        'ascension': ascension,
        'constellation': constellation,
        'talent_normal': talentNormal,
        'talent_skill': talentSkill,
        'talent_burst': talentBurst,
        'weapon_id': weaponId,
        'weapon_name': weaponName,
        'weapon_level': weaponLevel,
        'weapon_refinement': weaponRefinement,
        'artifacts': artifactsJson,
        'is_completed': isCompleted ? 1 : 0,
        'memo': memo,
        'artifact_score_type': artifactScoreType,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory UserProgress.fromMap(Map<String, Object?> map) => UserProgress(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        characterId: map['character_id'] as String,
        level: map['level'] as int? ?? 1,
        ascension: map['ascension'] as int? ?? 0,
        constellation: map['constellation'] as int? ?? 0,
        talentNormal: map['talent_normal'] as int? ?? 1,
        talentSkill: map['talent_skill'] as int? ?? 1,
        talentBurst: map['talent_burst'] as int? ?? 1,
        weaponId: map['weapon_id'] as String? ?? '',
        weaponName: map['weapon_name'] as String? ?? '',
        weaponLevel: map['weapon_level'] as int? ?? 1,
        weaponRefinement: map['weapon_refinement'] as int? ?? 1,
        artifactsJson: map['artifacts'] as String? ?? '{}',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        memo: map['memo'] as String? ?? '',
        artifactScoreType: map['artifact_score_type'] as String? ?? '',
      );

  UserProgress copyWith({
    int? level,
    int? ascension,
    int? constellation,
    int? talentNormal,
    int? talentSkill,
    int? talentBurst,
    int? weaponLevel,
    int? weaponRefinement,
    String? weaponId,
    String? weaponName,
    String? artifactScoreType,
    String? artifactsJson,
    ArtifactState? artifacts,
  }) {
    return UserProgress(
      id: id,
      userId: userId,
      characterId: characterId,
      level: level ?? this.level,
      ascension: ascension ?? this.ascension,
      constellation: constellation ?? this.constellation,
      talentNormal: talentNormal ?? this.talentNormal,
      talentSkill: talentSkill ?? this.talentSkill,
      talentBurst: talentBurst ?? this.talentBurst,
      weaponId: weaponId ?? this.weaponId,
      weaponName: weaponName ?? this.weaponName,
      weaponLevel: weaponLevel ?? this.weaponLevel,
      weaponRefinement: weaponRefinement ?? this.weaponRefinement,
      artifactScoreType: artifactScoreType ?? this.artifactScoreType,
      artifactsJson: artifactsJson ??
          (artifacts != null ? encodeArtifactState(artifacts) : this.artifactsJson),
      isCompleted: isCompleted,
      memo: memo,
    );
  }
}
