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
      mainStat:
          main == null
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
      mainStat:
          main == null
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

  factory GameRecordTalent.fromJson(Map<String, dynamic> json) =>
      GameRecordTalent(
        name: json['name'] as String? ?? json['skill_name'] as String? ?? '天賦',
        level: _asInt(json['level'] ?? json['level_current']),
      );
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
