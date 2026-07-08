/// HoYoLAB ゲーム記録 API モデル（Battle Chronicle）
library;

class GameRecordProp {
  const GameRecordProp({required this.label, required this.value});

  final String label;
  final String value;

  static GameRecordProp? fromJson(Map<String, dynamic> json) {
    final label = json['name'] as String? ??
        json['property_name'] as String? ??
        _propTypeLabel(json['prop_type'] as String?);
    final raw = json['value'] ?? json['final'] ?? json['base'];
    if (label == null || raw == null) return null;
    return GameRecordProp(label: label, value: '$raw');
  }

  static String? _propTypeLabel(String? type) {
    return switch (type) {
      'FIGHT_PROP_HP' || 'FIGHT_PROP_BASE_HP' || 'FIGHT_PROP_HP_PERCENT' =>
        'HP',
      'FIGHT_PROP_ATTACK' ||
      'FIGHT_PROP_BASE_ATTACK' ||
      'FIGHT_PROP_ATTACK_PERCENT' =>
        '攻撃力',
      'FIGHT_PROP_DEFENSE' ||
      'FIGHT_PROP_BASE_DEFENSE' ||
      'FIGHT_PROP_DEFENSE_PERCENT' =>
        '防御力',
      'FIGHT_PROP_ELEMENT_MASTERY' => '元素熟知',
      'FIGHT_PROP_CRITICAL' => '会心率',
      'FIGHT_PROP_CRITICAL_HURT' => '会心ダメージ',
      'FIGHT_PROP_CHARGE_EFFICIENCY' => '元素チャージ効率',
      'FIGHT_PROP_HEAL_ADD' => '与える治療効果',
      'FIGHT_PROP_HEALED_ADD' => '受ける治療効果',
      'FIGHT_PROP_PHYSICAL_ADD_HURT' => '物理ダメージ',
      _ => type,
    };
  }
}

class GameRecordWeapon {
  const GameRecordWeapon({
    required this.id,
    required this.name,
    required this.level,
    this.refinement = 1,
    this.promoteLevel = 0,
    this.rarity = 3,
    this.mainStat,
    this.subStats = const [],
  });

  final String id;
  final String name;
  final int level;
  final int refinement;
  final int promoteLevel;
  final int rarity;
  final GameRecordProp? mainStat;
  final List<GameRecordProp> subStats;

  factory GameRecordWeapon.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GameRecordWeapon(id: '', name: '', level: 1);
    }
    final main = json['main_property'] as Map<String, dynamic>?;
    final subs = <GameRecordProp>[];
    final subList = json['sub_property_list'] as List<dynamic>? ?? [];
    for (final raw in subList) {
      final prop = GameRecordProp.fromJson(raw as Map<String, dynamic>);
      if (prop != null) subs.add(prop);
    }
    return GameRecordWeapon(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      level: _asInt(json['level']),
      refinement: _asInt(json['affix_level'], fallback: 1),
      promoteLevel: _asInt(json['promote_level']),
      rarity: _asInt(json['rarity'], fallback: 3),
      mainStat: main == null ? null : GameRecordProp.fromJson(main),
      subStats: subs,
    );
  }
}

class GameRecordRelic {
  const GameRecordRelic({
    required this.id,
    required this.name,
    required this.posName,
    required this.level,
    this.setName = '',
    this.mainStat,
    this.subStats = const [],
  });

  final String id;
  final String name;
  final String posName;
  final int level;
  final String setName;
  final GameRecordProp? mainStat;
  final List<GameRecordProp> subStats;

  factory GameRecordRelic.fromJson(Map<String, dynamic> json) {
    final set = json['set'] as Map<String, dynamic>?;
    final main = json['main_property'] as Map<String, dynamic>?;
    final subs = <GameRecordProp>[];
    final subList = json['sub_property_list'] as List<dynamic>? ?? [];
    for (final raw in subList) {
      final prop = GameRecordProp.fromJson(raw as Map<String, dynamic>);
      if (prop != null) subs.add(prop);
    }
    return GameRecordRelic(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      posName: json['pos_name'] as String? ?? '',
      level: _asInt(json['level']),
      setName: set?['name'] as String? ?? '',
      mainStat: main == null ? null : GameRecordProp.fromJson(main),
      subStats: subs,
    );
  }
}

class GameRecordTalent {
  const GameRecordTalent({required this.name, required this.level});

  final String name;
  final int level;

  factory GameRecordTalent.fromJson(Map<String, dynamic> json) => GameRecordTalent(
        name: json['name'] as String? ?? json['skill_name'] as String? ?? '天賦',
        level: _asInt(json['level'] ?? json['level_current']),
      );
}

class HoyolabOwnedCharacter {
  const HoyolabOwnedCharacter({
    required this.id,
    required this.name,
    required this.level,
    this.friendship = 0,
    this.constellation = 0,
    this.promoteLevel = 0,
    this.obtainedAt,
    this.iconUrl,
    this.weapon,
    this.relics = const [],
  });

  final String id;
  final String name;
  final int level;
  final int friendship;
  final int constellation;
  final int promoteLevel;
  final DateTime? obtainedAt;
  final String? iconUrl;
  final GameRecordWeapon? weapon;
  final List<GameRecordRelic> relics;

  bool get isOwned => true;

  factory HoyolabOwnedCharacter.fromSummaryJson(Map<String, dynamic> json) {
    final weaponRaw = json['weapon'] as Map<String, dynamic>?;
    final relicsRaw = json['reliquaries'] as List<dynamic>? ?? [];
    return HoyolabOwnedCharacter(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      level: _asInt(json['level']),
      friendship: _asInt(json['fetter']),
      constellation: _asInt(json['actived_constellation_num']),
      promoteLevel: _asInt(json['promote_level']),
      iconUrl: json['icon'] as String?,
      weapon: weaponRaw == null
          ? null
          : GameRecordWeapon.fromJson(weaponRaw),
      relics: relicsRaw
          .map((e) => GameRecordRelic.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HoyolabCharacterBuild {
  const HoyolabCharacterBuild({
    required this.id,
    required this.isOwned,
    this.level = 1,
    this.promoteLevel = 0,
    this.friendship = 0,
    this.constellation = 0,
    this.stats = const [],
    this.talents = const [],
    this.weapon,
    this.relics = const [],
    this.fetchedAt,
  });

  final String id;
  final bool isOwned;
  final int level;
  final int promoteLevel;
  final int friendship;
  final int constellation;
  final List<GameRecordProp> stats;
  final List<GameRecordTalent> talents;
  final GameRecordWeapon? weapon;
  final List<GameRecordRelic> relics;
  final DateTime? fetchedAt;

  factory HoyolabCharacterBuild.unowned(String id) =>
      HoyolabCharacterBuild(id: id, isOwned: false);

  factory HoyolabCharacterBuild.fromDetailJson(
    Map<String, dynamic> json, {
    HoyolabOwnedCharacter? summary,
  }) {
    final base = json['base'] as Map<String, dynamic>? ?? json;
    final id = '${base['id'] ?? summary?.id ?? ''}';
    final stats = <GameRecordProp>[];
    for (final key in [
      'base_properties',
      'extra_properties',
      'element_properties',
      'selected_properties',
    ]) {
      final list = json[key] as List<dynamic>? ?? [];
      for (final raw in list) {
        final prop = GameRecordProp.fromJson(raw as Map<String, dynamic>);
        if (prop != null) stats.add(prop);
      }
    }

    final talents = <GameRecordTalent>[];
    final skills = json['skills'] as List<dynamic>? ??
        json['skill_list'] as List<dynamic>? ??
        [];
    for (final raw in skills) {
      talents.add(GameRecordTalent.fromJson(raw as Map<String, dynamic>));
    }

    final relics = <GameRecordRelic>[];
    final relicList =
        json['relics'] as List<dynamic>? ?? json['reliquary_list'] as List<dynamic>? ?? [];
    for (final raw in relicList) {
      relics.add(GameRecordRelic.fromJson(raw as Map<String, dynamic>));
    }

    return HoyolabCharacterBuild(
      id: id,
      isOwned: true,
      level: _asInt(base['level'], fallback: summary?.level ?? 1),
      promoteLevel: _asInt(
        base['promote_level'] ?? base['promoteLevel'],
        fallback: summary?.promoteLevel ?? 0,
      ),
      friendship: _asInt(base['fetter'], fallback: summary?.friendship ?? 0),
      constellation: _asInt(
        base['actived_constellation_num'],
        fallback: summary?.constellation ?? 0,
      ),
      stats: stats,
      talents: talents,
      weapon: GameRecordWeapon.fromJson(
        json['weapon'] as Map<String, dynamic>? ??
            _weaponToJson(summary?.weapon),
      ),
      relics: relics.isNotEmpty ? relics : (summary?.relics ?? const []),
      fetchedAt: DateTime.now(),
    );
  }

  HoyolabCharacterBuild mergeSummary(HoyolabOwnedCharacter summary) {
    if (!summary.id.startsWith(id) && summary.id != id) return this;
    return HoyolabCharacterBuild(
      id: id,
      isOwned: true,
      level: level > 1 ? level : summary.level,
      promoteLevel: promoteLevel > 0 ? promoteLevel : summary.promoteLevel,
      friendship: friendship > 0 ? friendship : summary.friendship,
      constellation:
          constellation > 0 ? constellation : summary.constellation,
      stats: stats,
      talents: talents,
      weapon: weapon ?? summary.weapon,
      relics: relics.isNotEmpty ? relics : summary.relics,
      fetchedAt: fetchedAt,
    );
  }

  String? statValue(String label) {
    for (final stat in stats) {
      if (stat.label.contains(label)) return stat.value;
    }
    return null;
  }
}

Map<String, dynamic>? _weaponToJson(GameRecordWeapon? weapon) {
  if (weapon == null) return null;
  return {
    'id': weapon.id,
    'name': weapon.name,
    'level': weapon.level,
    'affix_level': weapon.refinement,
    'promote_level': weapon.promoteLevel,
    'rarity': weapon.rarity,
  };
}

class SpiralAbyssStatus {
  const SpiralAbyssStatus({
    required this.maxFloor,
    required this.totalStars,
    required this.isUnlocked,
    this.scheduleId,
    this.updatedAt,
  });

  final String maxFloor;
  final int totalStars;
  final bool isUnlocked;
  final int? scheduleId;
  final DateTime? updatedAt;

  factory SpiralAbyssStatus.fromJson(Map<String, dynamic> json) {
    final start = int.tryParse('${json['start_time'] ?? ''}');
    return SpiralAbyssStatus(
      maxFloor: json['max_floor'] as String? ?? '-',
      totalStars: _asInt(json['total_star']),
      isUnlocked: json['is_unlock'] as bool? ?? false,
      scheduleId: _asInt(json['schedule_id']),
      updatedAt: start == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(start * 1000),
    );
  }
}

class ImaginariumTheaterStatus {
  const ImaginariumTheaterStatus({
    required this.isUnlocked,
    required this.difficultyId,
    required this.maxRoundId,
    required this.medalNum,
    this.hasData = false,
    this.updatedAt,
    this.highlightAvatars = const [],
  });

  final bool isUnlocked;
  final int difficultyId;
  final int maxRoundId;
  final int medalNum;
  final bool hasData;
  final DateTime? updatedAt;
  final List<String> highlightAvatars;

  String get difficultyLabel => switch (difficultyId) {
        1 => 'イージー',
        2 => 'ノーマル',
        3 => 'ハード',
        4 => 'エキスパート',
        5 => 'アルカナ',
        _ => '難易度 $difficultyId',
      };

  factory ImaginariumTheaterStatus.fromSeasonJson(Map<String, dynamic> json) {
    final stat = json['stat'] as Map<String, dynamic>? ?? {};
    final schedule = json['schedule'] as Map<String, dynamic>? ?? {};
    final detail = json['detail'] as Map<String, dynamic>?;
    final avatars = <String>[];
    final rounds = detail?['rounds_data'] as List<dynamic>? ?? [];
    for (final round in rounds.take(2)) {
      final list = (round as Map<String, dynamic>)['avatars'] as List<dynamic>? ?? [];
      for (final avatar in list.take(4)) {
        final icon = (avatar as Map<String, dynamic>)['icon'] as String?;
        if (icon != null) avatars.add(icon);
      }
    }

    DateTime? updatedAt;
    final end = schedule['end_date_time'] as Map<String, dynamic>?;
    if (end != null) {
      updatedAt = DateTime(
        _asInt(end['year'], fallback: 1970),
        _asInt(end['month'], fallback: 1),
        _asInt(end['day'], fallback: 1),
      );
    }

    return ImaginariumTheaterStatus(
      isUnlocked: json['is_unlock'] as bool? ?? true,
      difficultyId: _asInt(stat['difficulty_id'], fallback: 1),
      maxRoundId: _asInt(stat['max_round_id']),
      medalNum: _asInt(stat['medal_num']),
      hasData: json['has_data'] as bool? ?? stat.isNotEmpty,
      updatedAt: updatedAt,
      highlightAvatars: avatars,
    );
  }
}

class AdventureStatus {
  const AdventureStatus({
    this.spiralAbyss,
    this.imaginariumTheater,
    this.fetchedAt,
  });

  final SpiralAbyssStatus? spiralAbyss;
  final ImaginariumTheaterStatus? imaginariumTheater;
  final DateTime? fetchedAt;

  DateTime? get latestUpdate {
    final dates = [
      spiralAbyss?.updatedAt,
      imaginariumTheater?.updatedAt,
      fetchedAt,
    ].whereType<DateTime>();
    if (dates.isEmpty) return fetchedAt;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String? formatRelativeObtained(DateTime? obtainedAt) {
  if (obtainedAt == null) return null;
  final days = DateTime.now().difference(obtainedAt).inDays;
  if (days <= 0) return '取得 今日';
  if (days < 30) return '取得 $days日前';
  final months = (days / 30).floor();
  return '取得 約$monthsヶ月前';
}
