import 'game_record_props.dart';

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
  }) => HoyolabOwnedCharacter(
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
    final relicsRaw =
        json['reliquaries'] as List<dynamic>? ??
        json['relics'] as List<dynamic>? ??
        json['reliquary_list'] as List<dynamic>? ??
        [];
    return HoyolabOwnedCharacter(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? '',
      level: _asInt(json['level']),
      friendship: _asInt(json['fetter']),
      constellation: _asInt(json['actived_constellation_num']),
      promoteLevel: _asInt(json['promote_level']),
      obtainedAt: parseObtainedAtFromCharacterJson(json),
      iconUrl: json['icon'] as String?,
      weapon: weaponRaw == null ? null : GameRecordWeapon.fromJson(weaponRaw),
      relics:
          relicsRaw
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
    final normalized =
        trimmed.contains('T') ? trimmed : trimmed.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }
  return null;
}

String? formatRelativeObtained(DateTime? obtainedAt) {
  if (obtainedAt == null) return null;
  final days = DateTime.now().difference(obtainedAt).inDays;
  if (days <= 0) return '取得 今日';
  if (days < 30) return '取得 $days日前';
  final months = (days / 30).floor();
  return '取得 約$monthsヶ月前';
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
