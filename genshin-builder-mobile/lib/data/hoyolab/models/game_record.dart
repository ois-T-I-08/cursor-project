/// HoYoLAB ゲーム記録 API モデル（Battle Chronicle）
library;

import '../../../domain/hoyolab_stat_normalize.dart';

/// property_map の 1 エントリ（property_type → 表示名）
class GameRecordPropertyInfo {
  const GameRecordPropertyInfo({
    required this.type,
    required this.name,
    this.filterName = '',
  });

  final int type;
  final String name;
  final String filterName;

  factory GameRecordPropertyInfo.fromJson(Map<String, dynamic> json) {
    return GameRecordPropertyInfo(
      type: _asInt(json['property_type'] ?? json['type']),
      name: json['name'] as String? ?? '',
      filterName: json['filter_name'] as String? ?? '',
    );
  }
}

typedef GameRecordPropertyMap = Map<int, GameRecordPropertyInfo>;

GameRecordPropertyMap parseGameRecordPropertyMap(dynamic raw) {
  if (raw is! Map) return {};
  final map = <int, GameRecordPropertyInfo>{};
  for (final entry in raw.entries) {
    final typeId = int.tryParse('${entry.key}');
    final value = entry.value;
    if (typeId == null || value is! Map) continue;
    map[typeId] = GameRecordPropertyInfo.fromJson(
      Map<String, dynamic>.from(value),
    );
  }
  return map;
}

class GameRecordProp {
  const GameRecordProp({required this.label, required this.value});

  final String label;
  final String value;

  static GameRecordProp? fromJson(
    Map<String, dynamic> json, {
    GameRecordPropertyMap propertyMap = const {},
  }) {
    final label = _resolveLabel(json, propertyMap);
    final raw = json['value'] ?? json['final'] ?? json['base'] ?? json['add'];
    if (label == null || raw == null) return null;
    return GameRecordProp(label: label, value: '$raw');
  }

  static String? _resolveLabel(
    Map<String, dynamic> json,
    GameRecordPropertyMap propertyMap,
  ) {
    final info = json['info'];
    if (info is Map<String, dynamic>) {
      final name = info['name'] as String?;
      if (name != null && name.isNotEmpty) return name;
      final filter = labelFromFilterName(info['filter_name'] as String?);
      if (filter != null) return filter;
    }

    final direct = json['name'] as String? ?? json['property_name'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;

    final propType = json['property_type'] ?? json['prop_type'];
    if (propType is num) {
      final mapped = propertyMap[propType.toInt()];
      if (mapped != null && mapped.name.isNotEmpty) return mapped.name;
      final filter = labelFromFilterName(mapped?.filterName);
      if (filter != null) return filter;
    }
    if (propType is String) {
      return _propTypeLabel(propType) ?? labelFromFilterName(propType);
    }

    return null;
  }

  static String? _propTypeLabel(String? type) {
    if (type == null || type.isEmpty) return null;
    return labelFromFilterName(type) ?? type;
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
    this.iconUrl,
  });

  final String id;
  final String name;
  final int level;
  final int refinement;
  final int promoteLevel;
  final int rarity;
  final GameRecordProp? mainStat;
  final List<GameRecordProp> subStats;
  final String? iconUrl;

  factory GameRecordWeapon.fromJson(
    Map<String, dynamic>? json, {
    GameRecordPropertyMap propertyMap = const {},
  }) {
    if (json == null) {
      return const GameRecordWeapon(id: '', name: '', level: 1);
    }
    final main = json['main_property'] as Map<String, dynamic>?;
    final subs = <GameRecordProp>[];
    final subList = json['sub_property_list'] as List<dynamic>? ?? [];
    for (final raw in subList) {
      final prop = GameRecordProp.fromJson(
        raw as Map<String, dynamic>,
        propertyMap: propertyMap,
      );
      if (prop != null) subs.add(prop);
    }
    return GameRecordWeapon(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      level: _asInt(json['level']),
      refinement: _asInt(json['affix_level'], fallback: 1),
      promoteLevel: _asInt(json['promote_level']),
      rarity: _asInt(json['rarity'], fallback: 3),
      mainStat: main == null
          ? null
          : GameRecordProp.fromJson(main, propertyMap: propertyMap),
      subStats: subs,
      iconUrl: json['icon'] as String?,
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
    this.iconUrl,
  });

  final String id;
  final String name;
  final String posName;
  final int level;
  final String setName;
  final GameRecordProp? mainStat;
  final List<GameRecordProp> subStats;
  final String? iconUrl;

  factory GameRecordRelic.fromJson(
    Map<String, dynamic> json, {
    GameRecordPropertyMap propertyMap = const {},
  }) {
    final set = json['set'] as Map<String, dynamic>?;
    final main = json['main_property'] as Map<String, dynamic>?;
    final subs = <GameRecordProp>[];
    final subList = json['sub_property_list'] as List<dynamic>? ?? [];
    for (final raw in subList) {
      final prop = GameRecordProp.fromJson(
        raw as Map<String, dynamic>,
        propertyMap: propertyMap,
      );
      if (prop != null) subs.add(prop);
    }
    return GameRecordRelic(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      posName: json['pos_name'] as String? ?? '',
      level: _asInt(json['level']),
      setName: set?['name'] as String? ?? '',
      mainStat: main == null
          ? null
          : GameRecordProp.fromJson(main, propertyMap: propertyMap),
      subStats: subs,
      iconUrl: json['icon'] as String?,
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

  HoyolabOwnedCharacter copyWith({
    String? id,
    String? name,
    int? level,
    int? friendship,
    int? constellation,
    int? promoteLevel,
    DateTime? obtainedAt,
    String? iconUrl,
    GameRecordWeapon? weapon,
    List<GameRecordRelic>? relics,
  }) =>
      HoyolabOwnedCharacter(
        id: id ?? this.id,
        name: name ?? this.name,
        level: level ?? this.level,
        friendship: friendship ?? this.friendship,
        constellation: constellation ?? this.constellation,
        promoteLevel: promoteLevel ?? this.promoteLevel,
        obtainedAt: obtainedAt ?? this.obtainedAt,
        iconUrl: iconUrl ?? this.iconUrl,
        weapon: weapon ?? this.weapon,
        relics: relics ?? this.relics,
      );

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
      obtainedAt: parseObtainedAtFromCharacterJson(json),
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

/// HoYoLAB キャラ JSON から取得日時を抽出（公式フィールド未定義のため複数候補を試す）
DateTime? parseObtainedAtFromCharacterJson(Map<String, dynamic> json) {
  const keys = [
    'obtained_time',
    'obtain_time',
    'wear_time',
    'get_time',
    'create_time',
    'active_time',
    'obtained_at',
    'wearer_time',
  ];

  for (final key in keys) {
    final parsed = parseFlexibleDateTime(json[key]);
    if (parsed != null) return parsed;
  }

  final external = json['external'];
  if (external is Map) {
    final map = Map<String, dynamic>.from(external);
    for (final key in keys) {
      final parsed = parseFlexibleDateTime(map[key]);
      if (parsed != null) return parsed;
    }
  }

  return null;
}

DateTime? parseFlexibleDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is int) {
    final millis = raw > 9999999999 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (raw is num) {
    final value = raw.toInt();
    final millis = value > 9999999999 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final unix = int.tryParse(trimmed);
    if (unix != null) {
      final millis = unix > 9999999999 ? unix : unix * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final normalized = trimmed.contains('T') ? trimmed : trimmed.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }
  return null;
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
    GameRecordPropertyMap propertyMap = const {},
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
        final prop = GameRecordProp.fromJson(
          raw as Map<String, dynamic>,
          propertyMap: propertyMap,
        );
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
      relics.add(
        GameRecordRelic.fromJson(
          raw as Map<String, dynamic>,
          propertyMap: propertyMap,
        ),
      );
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
        propertyMap: propertyMap,
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
    final cachedAt = json['updated_at'] as String?;
    if (cachedAt != null) {
      return SpiralAbyssStatus(
        maxFloor: json['max_floor'] as String? ?? '-',
        totalStars: _asInt(json['total_star']),
        isUnlocked: json['is_unlock'] as bool? ?? false,
        scheduleId: json['schedule_id'] == null
            ? null
            : _asInt(json['schedule_id']),
        updatedAt: DateTime.tryParse(cachedAt),
      );
    }

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

  Map<String, dynamic> toJson() => {
        'max_floor': maxFloor,
        'total_star': totalStars,
        'is_unlock': isUnlocked,
        if (scheduleId != null) 'schedule_id': scheduleId,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
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

  factory ImaginariumTheaterStatus.fromCacheJson(Map<String, dynamic> json) =>
      ImaginariumTheaterStatus(
        isUnlocked: json['is_unlock'] as bool? ?? true,
        difficultyId: _asInt(json['difficulty_id'], fallback: 1),
        maxRoundId: _asInt(json['max_round_id']),
        medalNum: _asInt(json['medal_num']),
        hasData: json['has_data'] as bool? ?? false,
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(json['updated_at'] as String),
        highlightAvatars: (json['highlight_avatars'] as List<dynamic>? ?? [])
            .map((e) => '$e')
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        'is_unlock': isUnlocked,
        'difficulty_id': difficultyId,
        'max_round_id': maxRoundId,
        'medal_num': medalNum,
        'has_data': hasData,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        'highlight_avatars': highlightAvatars,
      };
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

  factory AdventureStatus.fromCacheJson(Map<String, dynamic> json) =>
      AdventureStatus(
        spiralAbyss: json['spiral_abyss'] == null
            ? null
            : SpiralAbyssStatus.fromJson(
                json['spiral_abyss'] as Map<String, dynamic>,
              ),
        imaginariumTheater: json['imaginarium_theater'] == null
            ? null
            : ImaginariumTheaterStatus.fromCacheJson(
                json['imaginarium_theater'] as Map<String, dynamic>,
              ),
        fetchedAt: json['fetched_at'] == null
            ? null
            : DateTime.tryParse(json['fetched_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        if (spiralAbyss != null) 'spiral_abyss': spiralAbyss!.toJson(),
        if (imaginariumTheater != null)
          'imaginarium_theater': imaginariumTheater!.toJson(),
        if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String(),
      };
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
