import '../../data/hoyolab/hoyolab_relic_sync.dart';
import '../../data/hoyolab/models/game_record.dart';
import '../../domain/hoyolab_stat_normalize.dart';
import '../../domain/models/master_models.dart';
import '../../domain/team_recommendation/team_recommendation.dart';

const _idPattern = r'^\d{5,12}$';
const _elements = {
  'anemo',
  'cryo',
  'dendro',
  'electro',
  'geo',
  'hydro',
  'pyro',
};

/// Builds API-safe team-recommendation snapshots. Entries that cannot satisfy
/// the backend contract (non-numeric ids, invalid element/rarity, etc.) are omitted.
List<SimulationBuildSnapshot> normalizeSimulationBuilds({
  required List<MasterCharacter> characters,
  required Map<String, HoyolabCharacterBuild> hoyolabBuilds,
  required Map<String, UserProgress> localProgress,
}) {
  final out = <SimulationBuildSnapshot>[];
  for (final character in characters) {
    final snapshot = _normalizeOne(
      character: character,
      build: hoyolabBuilds[character.id],
      progress: localProgress[character.id],
    );
    if (snapshot != null) out.add(snapshot);
    if (out.length >= 256) break;
  }
  return out;
}

SimulationBuildSnapshot? _normalizeOne({
  required MasterCharacter character,
  required HoyolabCharacterBuild? build,
  required UserProgress? progress,
}) {
  if (!RegExp(_idPattern).hasMatch(character.id)) return null;
  final element = character.element.toLowerCase();
  if (!_elements.contains(element)) return null;
  if (character.rarity != 4 && character.rarity != 5) return null;

  if (build == null && progress == null) {
    return SimulationBuildSnapshot(
      characterId: character.id,
      element: element,
      rarity: character.rarity,
      isOwned: false,
      level: 1,
      ascension: 0,
      constellation: 0,
      inputQuality: SimulationInputQuality.unsupported,
      defaultedFields: const [
        'level',
        'ascension',
        'constellation',
        'talents',
        'weapon',
        'artifacts',
      ],
    );
  }

  final defaulted = <String>[];
  var usedDocumentedDefaults = false;
  final talents = _talents(build?.talents ?? const []);
  Map<String, int>? talentMap = talents;
  if (talentMap == null && progress != null) {
    talentMap = {
      'normal': _clampInt(progress.talentNormal, 1, 15),
      'skill': _clampInt(progress.talentSkill, 1, 15),
      'burst': _clampInt(progress.talentBurst, 1, 15),
    };
  }
  if (talentMap == null) {
    // Documented default: fill talents when ownership/progress exists.
    defaulted.add('talents');
    talentMap = const {'normal': 1, 'skill': 1, 'burst': 1};
    usedDocumentedDefaults = true;
  }

  var weapon = _weapon(build?.weapon);
  if (weapon == null) {
    defaulted.add('weapon');
    weapon = _defaultWeapon(character.weaponType);
    usedDocumentedDefaults = true;
  }

  final artifactStats = _artifactStats(build?.relics ?? const []);
  Map<String, Object>? artifacts;
  if (build == null || build.relics.isEmpty) {
    defaulted.add('artifacts');
  } else {
    // Game Record relics have set names only; stable setId is unavailable.
    defaulted.add('artifactSets');
    artifacts = {'sets': const <Object>[], 'stats': artifactStats};
  }

  return SimulationBuildSnapshot(
    characterId: character.id,
    element: element,
    rarity: character.rarity,
    isOwned: build?.isOwned ?? true,
    level: _clampInt(build?.level ?? progress?.level ?? 1, 1, 90),
    ascension: _clampInt(
      build?.promoteLevel ?? progress?.ascension ?? 0,
      0,
      6,
    ),
    constellation: _clampInt(
      build?.constellation ?? progress?.constellation ?? 0,
      0,
      6,
    ),
    talents: talentMap,
    weapon: weapon,
    artifacts: artifacts,
    inputQuality:
        defaulted.isEmpty
            ? SimulationInputQuality.exact
            : usedDocumentedDefaults
            ? SimulationInputQuality.defaulted
            : SimulationInputQuality.partial,
    defaultedFields: defaulted,
  );
}

Map<String, int>? _talents(List<GameRecordTalent> talents) {
  int? normal;
  int? skill;
  int? burst;
  for (final talent in talents) {
    final name = talent.name.toLowerCase();
    if (name.contains('通常') || name.contains('normal')) {
      normal = _clampInt(talent.level, 1, 15);
    }
    if (name.contains('スキル') || name.contains('skill')) {
      skill = _clampInt(talent.level, 1, 15);
    }
    if (name.contains('爆発') || name.contains('burst')) {
      burst = _clampInt(talent.level, 1, 15);
    }
  }
  return normal != null && skill != null && burst != null
      ? {'normal': normal, 'skill': skill, 'burst': burst}
      : null;
}

Map<String, Object>? _weapon(GameRecordWeapon? weapon) {
  if (weapon == null || !RegExp(_idPattern).hasMatch(weapon.id)) return null;
  return {
    'weaponId': weapon.id,
    'level': _clampInt(weapon.level, 1, 90),
    'ascension': _clampInt(weapon.promoteLevel, 0, 6),
    'refinement': _clampInt(weapon.refinement <= 0 ? 1 : weapon.refinement, 1, 5),
  };
}

/// Documented Favonius placeholders when weapon data is missing.
Map<String, Object> _defaultWeapon(String weaponType) {
  const byType = <String, String>{
    'sword': '11401',
    'claymore': '12401',
    'polearm': '13407',
    'catalyst': '14401',
    'bow': '15401',
  };
  return {
    'weaponId': byType[weaponType.toLowerCase()] ?? '11401',
    'level': 1,
    'ascension': 0,
    'refinement': 1,
  };
}

Map<String, double> _artifactStats(List<GameRecordRelic> relics) {
  final result = <String, double>{};
  for (final relic in relics) {
    final props = [
      if (relic.mainStat != null) relic.mainStat!,
      ...relic.subStats,
    ];
    for (final prop in props) {
      final normalized = normalizeSubStatLabel(prop.label) ?? prop.label;
      final key = _statKey(normalized);
      if (key == null) continue;
      final value = parseStatValue(prop.value);
      if (!value.isFinite || value < 0 || value > 100000) continue;
      result[key] = (result[key] ?? 0) + value;
    }
  }
  return result;
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

String? _statKey(String label) => switch (label.replaceAll('％', '%')) {
  'HP' => 'hpFlat',
  'HP%' => 'hpPercent',
  '攻撃力' => 'atkFlat',
  '攻撃力%' => 'atkPercent',
  '防御力' => 'defFlat',
  '防御力%' => 'defPercent',
  '会心率' => 'critRate',
  '会心ダメージ' => 'critDamage',
  '元素チャージ効率' => 'energyRecharge',
  '元素熟知' => 'elementalMastery',
  '炎元素ダメージ' => 'pyroDamageBonus',
  '水元素ダメージ' => 'hydroDamageBonus',
  '雷元素ダメージ' => 'electroDamageBonus',
  '氷元素ダメージ' => 'cryoDamageBonus',
  '風元素ダメージ' => 'anemoDamageBonus',
  '岩元素ダメージ' => 'geoDamageBonus',
  '草元素ダメージ' => 'dendroDamageBonus',
  '物理ダメージ' => 'physicalDamageBonus',
  _ => null,
};
