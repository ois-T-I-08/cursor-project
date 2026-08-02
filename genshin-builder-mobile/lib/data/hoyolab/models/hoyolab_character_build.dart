import 'game_record_props.dart';
import 'hoyolab_owned_character.dart';

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
    final skills =
        json['skills'] as List<dynamic>? ??
        json['skill_list'] as List<dynamic>? ??
        [];
    for (final raw in skills) {
      talents.add(GameRecordTalent.fromJson(raw as Map<String, dynamic>));
    }

    final relics = <GameRecordRelic>[];
    final relicList =
        json['relics'] as List<dynamic>? ??
        json['reliquary_list'] as List<dynamic>? ??
        [];
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
      constellation: constellation > 0 ? constellation : summary.constellation,
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

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
