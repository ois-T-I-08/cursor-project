import 'gacha_banner.dart';

/// アセット / リモートのバナー履歴スケジュール
class GachaBannerSchedule {
  const GachaBannerSchedule({
    required this.version,
    required this.banners,
  });

  final int version;
  final List<GachaBanner> banners;

  factory GachaBannerSchedule.fromJson(Map<String, dynamic> json) {
    validateGachaBannerScheduleJson(json);
    final raw = json['banners'] as List<dynamic>? ?? const [];
    return GachaBannerSchedule(
      version: (json['version'] as num?)?.toInt() ?? 1,
      banners: [
        for (final item in raw)
          if (item is Map<String, dynamic>) gachaBannerFromJson(item),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'banners': [for (final b in banners) gachaBannerToJson(b)],
      };
}

void validateGachaBannerScheduleJson(Map<String, dynamic> json) {
  final banners = json['banners'];
  if (banners is! List) {
    throw const FormatException('gacha_banner_history: banners must be a list');
  }
  for (final item in banners) {
    if (item is! Map) {
      throw const FormatException('gacha_banner_history: banner must be an object');
    }
    final map = Map<String, dynamic>.from(item);
    for (final key in ['id', 'type', 'name', 'start', 'end']) {
      if (map[key] == null || '${map[key]}'.trim().isEmpty) {
        throw FormatException('gacha_banner_history: missing $key');
      }
    }
    parseGachaBannerType('${map['type']}');
    DateTime.parse('${map['start']}');
    DateTime.parse('${map['end']}');
  }
}

GachaBannerType parseGachaBannerType(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'character':
    case 'character_event':
      return GachaBannerType.character;
    case 'character2':
    case 'character_event_2':
      return GachaBannerType.character2;
    case 'weapon':
    case 'weapon_event':
      return GachaBannerType.weapon;
    case 'chronicled':
    case 'chronicled_wish':
      return GachaBannerType.chronicled;
    default:
      throw FormatException('unknown gacha banner type: $raw');
  }
}

String gachaBannerTypeToJson(GachaBannerType type) => switch (type) {
      GachaBannerType.character => 'character',
      GachaBannerType.character2 => 'character2',
      GachaBannerType.weapon => 'weapon',
      GachaBannerType.chronicled => 'chronicled',
    };

GachaBanner gachaBannerFromJson(Map<String, dynamic> json) {
  List<String> ids(String key) {
    final raw = json[key];
    if (raw is! List) return const [];
    return [
      for (final x in raw)
        if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ];
  }

  final iconsRaw = json['sourceIcons'];
  final icons = <String, String>{};
  if (iconsRaw is Map) {
    for (final e in iconsRaw.entries) {
      final url = '${e.value}'.trim();
      if (url.isEmpty) continue;
      icons['${e.key}'] = url;
    }
  }

  return GachaBanner(
    id: '${json['id']}'.trim(),
    type: parseGachaBannerType('${json['type']}'),
    name: '${json['name']}'.trim(),
    version: '${json['version'] ?? ''}'.trim(),
    start: DateTime.parse('${json['start']}').toUtc(),
    end: DateTime.parse('${json['end']}').toUtc(),
    featured5Ids: ids('featured5Ids'),
    featured4Ids: ids('featured4Ids'),
    featuredWeaponIds: ids('featuredWeaponIds'),
    sourceIcons: icons,
  );
}

Map<String, dynamic> gachaBannerToJson(GachaBanner b) => {
      'id': b.id,
      'type': gachaBannerTypeToJson(b.type),
      'name': b.name,
      'version': b.version,
      'start': b.start.toUtc().toIso8601String(),
      'end': b.end.toUtc().toIso8601String(),
      'featured5Ids': b.featured5Ids,
      'featured4Ids': b.featured4Ids,
      'featuredWeaponIds': b.featuredWeaponIds,
      if (b.sourceIcons.isNotEmpty) 'sourceIcons': b.sourceIcons,
    };
