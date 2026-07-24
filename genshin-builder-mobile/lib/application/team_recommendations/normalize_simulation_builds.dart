import '../../data/hoyolab/hoyolab_relic_sync.dart';
import '../../data/hoyolab/models/game_record.dart';
import '../../domain/hoyolab_stat_normalize.dart';
import '../../domain/models/master_models.dart';
import '../../domain/team_recommendation/team_recommendation.dart';

final _apiId = RegExp(r'^\d{5,12}$');
const _elements = <String>{
  'anemo',
  'cryo',
  'dendro',
  'electro',
  'geo',
  'hydro',
  'pyro',
};

/// Backend `parseTeamRecommendationRequest` が受け付ける育成スナップショットへ正規化する。
/// 旅人の複合 ID など API 非対応のキャラは除外する。
List<SimulationBuildSnapshot> normalizeSimulationBuilds({
  required List<MasterCharacter> characters,
  required Map<String, HoyolabCharacterBuild> hoyolabBuilds,
  required Map<String, UserProgress> localProgress,
}) {
  final snapshots = <SimulationBuildSnapshot>[];
  for (final character in characters) {
    final snapshot = _normalizeOne(
      character: character,
      build: hoyolabBuilds[character.id],
      progress: localProgress[character.id],
    );
    if (snapshot != null) snapshots.add(snapshot);
  }
  return snapshots;
}

SimulationBuildSnapshot? _normalizeOne({
  required MasterCharacter character,
  required HoyolabCharacterBuild? build,
  required UserProgress? progress,
}) {
  if (!_apiId.hasMatch(character.id)) return null;
  if (character.rarity != 4 && character.rarity != 5) return null;
  final element = _normalizeElement(character.element);
  if (element == null) return null;

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
  final talents = _talents(build?.talents ?? const []);
  Map<String, int>? resolvedTalents = talents;
  if (resolvedTalents == null && progress != null) {
    resolvedTalents = _clampTalents({
      'normal': progress.talentNormal,
      'skill': progress.talentSkill,
      'burst': progress.talentBurst,
    });
  }
  if (resolvedTalents == null) defaulted.add('talents');

  final weapon = _weapon(build?.weapon);
  if (weapon == null) defaulted.add('weapon');

  final hasRelics = build?.relics.isNotEmpty == true;
  final artifactStats = hasRelics ? _artifactStats(build!.relics) : null;
  Map<String, Object>? artifacts;
  if (hasRelics) {
    // Game Record の聖遺物にはセット名だけがあり、安定した setId がないため推測しない。
    defaulted.add('artifactSets');
    artifacts = {'sets': const <Object>[], 'stats': artifactStats ?? const {}};
  } else {
    defaulted.add('artifacts');
  }

  final level = _bound(build?.level ?? progress?.level ?? 1, 1, 90);
  final ascension = _bound(
    build?.promoteLevel ?? progress?.ascension ?? 0,
    0,
    6,
  );
  final constellation = _bound(
    build?.constellation ?? progress?.constellation ?? 0,
    0,
    6,
  );

  return SimulationBuildSnapshot(
    characterId: character.id,
    element: element,
    rarity: character.rarity,
    isOwned: build?.isOwned ?? true,
    level: level,
    ascension: ascension,
    constellation: constellation,
    talents: resolvedTalents,
    weapon: weapon,
    artifacts: artifacts,
    inputQuality:
        defaulted.isEmpty
            ? SimulationInputQuality.exact
            : SimulationInputQuality.partial,
    defaultedFields: defaulted,
  );
}

String? _normalizeElement(String raw) {
  final value = raw.trim().toLowerCase();
  if (_elements.contains(value)) return value;
  return switch (value) {
    'electric' || 'electro' => 'electro',
    'fire' || 'pyro' => 'pyro',
    'water' || 'hydro' => 'hydro',
    'ice' || 'cryo' => 'cryo',
    'wind' || 'anemo' => 'anemo',
    'rock' || 'geo' => 'geo',
    'grass' || 'dendro' => 'dendro',
    _ => null,
  };
}

Map<String, int>? _talents(List<GameRecordTalent> talents) {
  int? normal;
  int? skill;
  int? burst;
  for (final talent in talents) {
    final name = talent.name.toLowerCase();
    if (name.contains('通常') || name.contains('normal')) normal = talent.level;
    if (name.contains('スキル') || name.contains('skill')) skill = talent.level;
    if (name.contains('爆発') || name.contains('burst')) burst = talent.level;
  }
  if (normal == null || skill == null || burst == null) return null;
  return _clampTalents({'normal': normal, 'skill': skill, 'burst': burst});
}

Map<String, int>? _clampTalents(Map<String, int> talents) {
  final normal = _clampInt(talents['normal'], 1, 15);
  final skill = _clampInt(talents['skill'], 1, 15);
  final burst = _clampInt(talents['burst'], 1, 15);
  if (normal == null || skill == null || burst == null) return null;
  return {'normal': normal, 'skill': skill, 'burst': burst};
}

Map<String, Object>? _weapon(GameRecordWeapon? weapon) {
  if (weapon == null || !_apiId.hasMatch(weapon.id)) return null;
  final level = _clampInt(weapon.level, 1, 90);
  final ascension = _clampInt(weapon.promoteLevel, 0, 6);
  final refinement = _clampInt(weapon.refinement, 1, 5);
  if (level == null || ascension == null || refinement == null) return null;
  return {
    'weaponId': weapon.id,
    'level': level,
    'ascension': ascension,
    'refinement': refinement,
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

int _bound(int value, int min, int max) => value.clamp(min, max);

int? _clampInt(int? value, int min, int max) {
  if (value == null) return null;
  if (value < min || value > max) return null;
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
