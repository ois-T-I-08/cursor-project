/// キャラクター最終ステータス計算エンジン（Web `stats.ts` 移植）
///
/// 以下を合算して最終ステータスを計算する。純 Dart 関数のため
/// 入力変更のたびに再計算でき、将来の編成シミュレーターからも再利用できる。
///   1. キャラクター基礎ステータス（レベル × 成長曲線 + 突破加算）
///   2. 武器ステータス（レベル別の基礎攻撃力・サブステータス）
///   3. 聖遺物メインステータス（★5 のレベル別数値を線形補間）
///   4. 聖遺物サブステータス（入力値）
///
/// セット効果・武器パッシブは呼び出し側で [activeSetEffects] を渡す（2セット常時補正のみ）。
library;

import 'models/amber_detail_models.dart';
import 'models/artifact_state.dart';

// ---------------------------------------------------------
// 表示キー
// ---------------------------------------------------------

enum StatKey {
  hp,
  atk,
  def,
  em,
  critRate,
  critDmg,
  er,
  healing,
  incomingHealing,
  shield,
  elemDmg,
  physDmg,
}

const statLabels = <StatKey, String>{
  StatKey.hp: 'HP',
  StatKey.atk: '攻撃力',
  StatKey.def: '防御力',
  StatKey.em: '元素熟知',
  StatKey.critRate: '会心率',
  StatKey.critDmg: '会心ダメージ',
  StatKey.er: '元素チャージ効率',
  StatKey.healing: '与える治療効果',
  StatKey.incomingHealing: '受ける治療効果',
  StatKey.shield: 'シールド強化',
  StatKey.elemDmg: '元素ダメージ',
  StatKey.physDmg: '物理ダメージ',
};

const percentStatKeys = <StatKey>{
  StatKey.critRate,
  StatKey.critDmg,
  StatKey.er,
  StatKey.healing,
  StatKey.incomingHealing,
  StatKey.shield,
  StatKey.elemDmg,
  StatKey.physDmg,
};

typedef StatValues = Map<StatKey, double>;

// ---------------------------------------------------------
// 計算用データモデル（Amber upgrade 正規化後）
// ---------------------------------------------------------

/// 基礎ステータス1項目分（Lv.1 初期値 + レベル別成長倍率）
class StatCurveProp {
  const StatCurveProp({
    required this.propType,
    required this.initValue,
    required this.curveValues,
  });

  /// FIGHT_PROP_BASE_HP など
  final String propType;
  final double initValue;

  /// index = レベル-1（Lv.1〜90）の成長倍率
  final List<double> curveValues;
}

/// 突破1段階分のステータス加算
class StatPromote {
  const StatPromote({
    required this.promoteLevel,
    required this.unlockMaxLevel,
    required this.addProps,
  });

  final int promoteLevel;
  final int unlockMaxLevel;

  /// FIGHT_PROP_* → 加算値（%系は小数。例: 0.384 = 38.4%）
  final Map<String, double> addProps;
}

/// キャラクターのステータス計算用データ
class AvatarStatsData {
  const AvatarStatsData({required this.props, required this.promotes});

  final List<StatCurveProp> props;
  final List<StatPromote> promotes;
}

/// 武器のあるレベル時点の実ステータス
class WeaponLevelStats {
  const WeaponLevelStats({
    required this.baseAttack,
    this.subStatProp,
    this.subStatValue,
  });

  final double baseAttack;

  /// サブステータスの FIGHT_PROP_*（無い武器は null）
  final String? subStatProp;

  /// %系は小数（0.144 = 14.4%）。元素熟知は実数
  final double? subStatValue;
}

/// 武器のステータス計算用データ
class WeaponStatsData {
  const WeaponStatsData({required this.props, required this.promotes});

  final List<StatCurveProp> props;
  final List<StatPromote> promotes;

  /// 指定レベル時点の基礎攻撃力・サブステータスを求める
  WeaponLevelStats statsAtLevel(int level) {
    final lv = level.clamp(1, 90);
    StatPromote? promote;
    final sorted = [...promotes]
      ..sort((a, b) => a.promoteLevel.compareTo(b.promoteLevel));
    for (final p in sorted) {
      if (p.unlockMaxLevel >= lv) {
        promote = p;
        break;
      }
    }
    promote ??= sorted.isEmpty ? null : sorted.last;

    var baseAttack = 0.0;
    String? subProp;
    double? subValue;

    for (final prop in props) {
      final curve = prop.curveValues.isEmpty ? 1.0 : prop.curveValues[lv - 1];
      if (prop.propType == 'FIGHT_PROP_BASE_ATTACK') {
        baseAttack =
            prop.initValue * curve +
            (promote?.addProps['FIGHT_PROP_BASE_ATTACK'] ?? 0);
      } else {
        subProp = prop.propType;
        subValue = prop.initValue * curve;
      }
    }

    return WeaponLevelStats(
      baseAttack: baseAttack,
      subStatProp: subProp,
      subStatValue: subValue,
    );
  }
}

// ---------------------------------------------------------
// 集計バケット
// ---------------------------------------------------------

class _StatBucket {
  double hpPct = 0;
  double hpFlat = 0;
  double atkPct = 0;
  double atkFlat = 0;
  double defPct = 0;
  double defFlat = 0;
  double em = 0;
  double critRate = 0;
  double critDmg = 0;
  double er = 0;
  double healing = 0;
  double incomingHealing = 0;
  double shield = 0;
  final Map<String, double> elemDmg = {};
  double physDmg = 0;
}

/// FIGHT_PROP_* をバケットへ加算する。
/// [fraction]=true のとき%系の値は小数（0.384 = 38.4%）として扱う。
void _applyFightProp(
  String propType,
  double value,
  _StatBucket bucket, {
  required bool fraction,
}) {
  final pct = fraction ? value * 100 : value;
  switch (propType) {
    case 'FIGHT_PROP_HP_PERCENT':
      bucket.hpPct += pct;
    case 'FIGHT_PROP_ATTACK_PERCENT':
      bucket.atkPct += pct;
    case 'FIGHT_PROP_DEFENSE_PERCENT':
      bucket.defPct += pct;
    case 'FIGHT_PROP_ELEMENT_MASTERY':
      bucket.em += value;
    case 'FIGHT_PROP_CRITICAL':
      bucket.critRate += pct;
    case 'FIGHT_PROP_CRITICAL_HURT':
      bucket.critDmg += pct;
    case 'FIGHT_PROP_CHARGE_EFFICIENCY':
      bucket.er += pct;
    case 'FIGHT_PROP_HEAL_ADD':
      bucket.healing += pct;
    case 'FIGHT_PROP_HEALED_ADD':
      bucket.incomingHealing += pct;
    case 'FIGHT_PROP_PHYSICAL_ADD_HURT':
      bucket.physDmg += pct;
    case 'FIGHT_PROP_FIRE_ADD_HURT':
      bucket.elemDmg['pyro'] = (bucket.elemDmg['pyro'] ?? 0) + pct;
    case 'FIGHT_PROP_WATER_ADD_HURT':
      bucket.elemDmg['hydro'] = (bucket.elemDmg['hydro'] ?? 0) + pct;
    case 'FIGHT_PROP_ELEC_ADD_HURT':
    case 'FIGHT_PROP_ELECTRIC_ADD_HURT':
      bucket.elemDmg['electro'] = (bucket.elemDmg['electro'] ?? 0) + pct;
    case 'FIGHT_PROP_ICE_ADD_HURT':
      bucket.elemDmg['cryo'] = (bucket.elemDmg['cryo'] ?? 0) + pct;
    case 'FIGHT_PROP_WIND_ADD_HURT':
      bucket.elemDmg['anemo'] = (bucket.elemDmg['anemo'] ?? 0) + pct;
    case 'FIGHT_PROP_ROCK_ADD_HURT':
      bucket.elemDmg['geo'] = (bucket.elemDmg['geo'] ?? 0) + pct;
    case 'FIGHT_PROP_GRASS_ADD_HURT':
      bucket.elemDmg['dendro'] = (bucket.elemDmg['dendro'] ?? 0) + pct;
  }
}

// ---------------------------------------------------------
// 聖遺物メインステータス（★5・レベル別数値の線形補間）
// ---------------------------------------------------------

const _mainStatRange = <String, ({double base, double max})>{
  'HP': (base: 717, max: 4780),
  '攻撃力': (base: 47, max: 311),
  'HP%': (base: 7.0, max: 46.6),
  '攻撃力%': (base: 7.0, max: 46.6),
  '防御力%': (base: 8.7, max: 58.3),
  '元素熟知': (base: 28, max: 186.5),
  '元素チャージ効率': (base: 7.8, max: 51.8),
  '会心率': (base: 4.7, max: 31.1),
  '会心ダメージ': (base: 9.3, max: 62.2),
  '与える治療効果': (base: 5.4, max: 35.9),
  '物理ダメージ': (base: 10.9, max: 58.3),
  '炎元素ダメージ': (base: 8.7, max: 46.6),
  '水元素ダメージ': (base: 8.7, max: 46.6),
  '雷元素ダメージ': (base: 8.7, max: 46.6),
  '氷元素ダメージ': (base: 8.7, max: 46.6),
  '風元素ダメージ': (base: 8.7, max: 46.6),
  '岩元素ダメージ': (base: 8.7, max: 46.6),
  '草元素ダメージ': (base: 8.7, max: 46.6),
};

/// ★5聖遺物メインステータスの数値をレベル（0〜20）から求める
double artifactMainStatValue(String statName, int level) {
  final range = _mainStatRange[statName];
  if (range == null) return 0;
  final t = level.clamp(0, 20) / 20;
  final value = range.base + (range.max - range.base) * t;
  return (value * 10).roundToDouble() / 10;
}

const _kanjiElementMap = <String, String>{
  '炎': 'pyro',
  '水': 'hydro',
  '雷': 'electro',
  '氷': 'cryo',
  '風': 'anemo',
  '岩': 'geo',
  '草': 'dendro',
};

final _elemDmgPattern = RegExp(r'^(炎|水|雷|氷|風|岩|草)元素ダメージ$');

/// セット効果テキストから常時補正を抽出（Web `SET_EFFECT_PATTERN` 相当）
final _setEffectPattern = RegExp(
  r'(シールド強化|与える治療効果|元素チャージ効率|元素熟知|会心率|会心ダメージ|攻撃力|防御力|HP|物理ダメージ|(?:炎|水|雷|氷|風|岩|草)元素ダメージ)\+([\d.]+)(%?)',
);

/// ステータス名（日本語ラベル）をバケットへ加算する
void _applyNamedStat(String stat, double value, _StatBucket bucket) {
  switch (stat) {
    case 'HP':
      bucket.hpFlat += value;
    case 'HP%':
      bucket.hpPct += value;
    case '攻撃力':
      bucket.atkFlat += value;
    case '攻撃力%':
      bucket.atkPct += value;
    case '防御力':
      bucket.defFlat += value;
    case '防御力%':
      bucket.defPct += value;
    case '元素熟知':
      bucket.em += value;
    case '会心率':
      bucket.critRate += value;
    case '会心ダメージ':
      bucket.critDmg += value;
    case '元素チャージ効率':
      bucket.er += value;
    case '与える治療効果':
      bucket.healing += value;
    case '物理ダメージ':
      bucket.physDmg += value;
    default:
      final match = _elemDmgPattern.firstMatch(stat);
      if (match != null) {
        final element = _kanjiElementMap[match.group(1)]!;
        bucket.elemDmg[element] = (bucket.elemDmg[element] ?? 0) + value;
      }
  }
}

/// セット効果の説明文から常時有効なステータス補正を加算する（Web 同等）
void _applySetEffectText(String text, _StatBucket bucket) {
  for (final match in _setEffectPattern.allMatches(text)) {
    final statName = match.group(1)!;
    final value = double.tryParse(match.group(2) ?? '');
    if (value == null) continue;
    final percent = match.group(3) ?? '';

    if (statName == 'シールド強化') {
      bucket.shield += value;
    } else if (statName == 'HP' || statName == '攻撃力' || statName == '防御力') {
      if (percent == '%') {
        _applyNamedStat('$statName%', value, bucket);
      }
    } else {
      _applyNamedStat(statName, value, bucket);
    }
  }
}

/// 装備中セットの2セット効果テキスト（2個以上装備）を解決する
List<String> resolveActiveTwoPieceSetEffects({
  required ArtifactState artifacts,
  required List<ArtifactSetDetail> sets,
}) {
  final counts = <String, int>{};
  for (final piece in artifacts.values) {
    final name = piece.setName.trim();
    if (name.isEmpty) continue;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final byName = {for (final s in sets) s.name: s};
  final effects = <String>[];
  for (final entry in counts.entries) {
    if (entry.value < 2) continue;
    final set = byName[entry.key];
    if (set == null || set.effects.isEmpty) continue;
    effects.add(set.effects.first);
  }
  return effects;
}

// ---------------------------------------------------------
// メイン計算
// ---------------------------------------------------------

double _round1(double n) => (n * 10).roundToDouble() / 10;

/// 最終ステータスを計算する
StatValues computeCharacterStats({
  required AvatarStatsData avatarStats,
  required String element,
  required int level,
  required int ascension,
  WeaponLevelStats? weapon,
  required ArtifactState artifacts,
  List<String> activeSetEffects = const [],
}) {
  final bucket = _StatBucket();

  // 1. キャラクター基礎（レベル × 曲線 + 突破加算）
  final sortedPromotes = [...avatarStats.promotes]
    ..sort((a, b) => a.promoteLevel.compareTo(b.promoteLevel));
  StatPromote? promote;
  final targetPromote = ascension.clamp(0, 6);
  for (final p in sortedPromotes) {
    if (p.promoteLevel == targetPromote) {
      promote = p;
      break;
    }
  }

  var baseHp = 0.0;
  var baseAtk = 0.0;
  var baseDef = 0.0;
  final lv = level.clamp(1, 90);

  for (final prop in avatarStats.props) {
    final curve = prop.curveValues.isEmpty ? 1.0 : prop.curveValues[lv - 1];
    final value =
        prop.initValue * curve + (promote?.addProps[prop.propType] ?? 0);
    switch (prop.propType) {
      case 'FIGHT_PROP_BASE_HP':
        baseHp = value;
      case 'FIGHT_PROP_BASE_ATTACK':
        baseAtk = value;
      case 'FIGHT_PROP_BASE_DEFENSE':
        baseDef = value;
    }
  }

  // 突破ボーナス（会心ダメ +38.4% など）
  if (promote != null) {
    for (final entry in promote.addProps.entries) {
      _applyFightProp(entry.key, entry.value, bucket, fraction: true);
    }
  }

  // 2. 武器（基礎攻撃力 + サブステータス）
  final weaponBaseAtk = weapon?.baseAttack ?? 0;
  if (weapon?.subStatProp != null && weapon?.subStatValue != null) {
    _applyFightProp(
      weapon!.subStatProp!,
      weapon.subStatValue!,
      bucket,
      fraction: true,
    );
  }

  // 3-4. 聖遺物（メイン + サブ）
  for (final piece in artifacts.values) {
    if (piece.mainStat.isNotEmpty) {
      _applyNamedStat(
        piece.mainStat,
        artifactMainStatValue(piece.mainStat, piece.level),
        bucket,
      );
    }
    for (final sub in piece.substats) {
      _applyNamedStat(sub.stat, sub.value, bucket);
    }
  }

  // 5. セット効果（2セットの常時補正テキスト）
  for (final text in activeSetEffects) {
    _applySetEffectText(text, bucket);
  }

  return {
    StatKey.hp:
        (baseHp * (1 + bucket.hpPct / 100) + bucket.hpFlat).roundToDouble(),
    StatKey.atk:
        ((baseAtk + weaponBaseAtk) * (1 + bucket.atkPct / 100) + bucket.atkFlat)
            .roundToDouble(),
    StatKey.def:
        (baseDef * (1 + bucket.defPct / 100) + bucket.defFlat).roundToDouble(),
    StatKey.em: bucket.em.roundToDouble(),
    StatKey.critRate: _round1(5 + bucket.critRate),
    StatKey.critDmg: _round1(50 + bucket.critDmg),
    StatKey.er: _round1(100 + bucket.er),
    StatKey.healing: _round1(bucket.healing),
    StatKey.incomingHealing: _round1(bucket.incomingHealing),
    StatKey.shield: _round1(bucket.shield),
    StatKey.elemDmg: _round1(bucket.elemDmg[element] ?? 0),
    StatKey.physDmg: _round1(bucket.physDmg),
  };
}

// ---------------------------------------------------------
// 基礎ステータス / 突破ボーナス（レベルタブ用）
// ---------------------------------------------------------

/// FIGHT_PROP_* → 日本語ラベル（突破ボーナス・武器サブステ用）
const fightPropLabels = <String, String>{
  'FIGHT_PROP_BASE_HP': '基礎HP',
  'FIGHT_PROP_BASE_ATTACK': '基礎攻撃力',
  'FIGHT_PROP_BASE_DEFENSE': '基礎防御力',
  'FIGHT_PROP_HP_PERCENT': 'HP',
  'FIGHT_PROP_ATTACK_PERCENT': '攻撃力',
  'FIGHT_PROP_DEFENSE_PERCENT': '防御力',
  'FIGHT_PROP_ELEMENT_MASTERY': '元素熟知',
  'FIGHT_PROP_CRITICAL': '会心率',
  'FIGHT_PROP_CRITICAL_HURT': '会心ダメージ',
  'FIGHT_PROP_CHARGE_EFFICIENCY': '元素チャージ効率',
  'FIGHT_PROP_HEAL_ADD': '与える治療効果',
  'FIGHT_PROP_PHYSICAL_ADD_HURT': '物理ダメージ',
  'FIGHT_PROP_FIRE_ADD_HURT': '炎元素ダメージ',
  'FIGHT_PROP_WATER_ADD_HURT': '水元素ダメージ',
  'FIGHT_PROP_ELEC_ADD_HURT': '雷元素ダメージ',
  'FIGHT_PROP_ELECTRIC_ADD_HURT': '雷元素ダメージ',
  'FIGHT_PROP_ICE_ADD_HURT': '氷元素ダメージ',
  'FIGHT_PROP_WIND_ADD_HURT': '風元素ダメージ',
  'FIGHT_PROP_ROCK_ADD_HURT': '岩元素ダメージ',
  'FIGHT_PROP_GRASS_ADD_HURT': '草元素ダメージ',
};

const _baseFightProps = {
  'FIGHT_PROP_BASE_HP',
  'FIGHT_PROP_BASE_ATTACK',
  'FIGHT_PROP_BASE_DEFENSE',
};

bool isPercentFightProp(String propType) =>
    propType != 'FIGHT_PROP_ELEMENT_MASTERY' &&
    !propType.startsWith('FIGHT_PROP_BASE_');

String formatFightPropValue(String propType, double value) {
  if (isPercentFightProp(propType)) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }
  return value.round().toString();
}

String fightPropLabel(String propType) => fightPropLabels[propType] ?? propType;

/// キャラクターの基礎 HP / 攻撃 / 防御（レベル × 曲線 + 突破加算）
class CharacterBaseStats {
  const CharacterBaseStats({
    required this.hp,
    required this.atk,
    required this.def,
  });

  final double hp;
  final double atk;
  final double def;
}

StatPromote? findPromoteByLevel(List<StatPromote> promotes, int promoteLevel) {
  for (final p in promotes) {
    if (p.promoteLevel == promoteLevel) return p;
  }
  return null;
}

CharacterBaseStats computeCharacterBaseStats({
  required AvatarStatsData avatarStats,
  required int level,
  required int ascension,
}) {
  final promote = findPromoteByLevel(
    avatarStats.promotes,
    ascension.clamp(0, 6),
  );
  final lv = level.clamp(1, 90);
  var baseHp = 0.0;
  var baseAtk = 0.0;
  var baseDef = 0.0;

  for (final prop in avatarStats.props) {
    final curve = prop.curveValues.isEmpty ? 1.0 : prop.curveValues[lv - 1];
    final value =
        prop.initValue * curve + (promote?.addProps[prop.propType] ?? 0);
    switch (prop.propType) {
      case 'FIGHT_PROP_BASE_HP':
        baseHp = value;
      case 'FIGHT_PROP_BASE_ATTACK':
        baseAtk = value;
      case 'FIGHT_PROP_BASE_DEFENSE':
        baseDef = value;
    }
  }

  return CharacterBaseStats(
    hp: baseHp.roundToDouble(),
    atk: baseAtk.roundToDouble(),
    def: baseDef.roundToDouble(),
  );
}

/// 突破ボーナス（基礎 HP/攻撃/防御を除く）を表示用に抽出する
Map<String, double> ascensionBonusProps(StatPromote? promote) {
  if (promote == null) return const {};
  return {
    for (final e in promote.addProps.entries)
      if (!_baseFightProps.contains(e.key) && e.value != 0) e.key: e.value,
  };
}

/// 突破段階の表示ラベル（例: 「Lv80突破済み」「未突破」）
String formatAscensionStageLabel({
  required int promoteLevel,
  required List<StatPromote> promotes,
}) {
  if (promoteLevel <= 0) return '未突破';
  final sorted = [...promotes]
    ..sort((a, b) => a.promoteLevel.compareTo(b.promoteLevel));
  StatPromote? prev;
  for (final p in sorted) {
    if (p.promoteLevel == promoteLevel - 1) {
      prev = p;
      break;
    }
  }
  final atLevel = prev?.unlockMaxLevel;
  if (atLevel == null) return '突破段階 $promoteLevel';
  return 'Lv$atLevel突破済み';
}

// ---------------------------------------------------------
// 差分（現在 ↔ 想定）
// ---------------------------------------------------------

class StatDeltaRow {
  const StatDeltaRow({
    required this.key,
    required this.label,
    required this.current,
    required this.simulated,
  });

  final StatKey key;
  final String label;
  final double current;
  final double simulated;

  double get delta => simulated - current;
  bool get isPercent => percentStatKeys.contains(key);
  bool get hasChange => delta.abs() >= 0.05;
}

/// 表示対象のステータス差分行を組み立てる。
/// [elementLabel] は元素ダメージ行のラベル（例: "炎元素ダメージ"）。
List<StatDeltaRow> buildStatDeltaRows({
  required StatValues current,
  required StatValues simulated,
  required String elementLabel,
}) {
  const mainKeys = [
    StatKey.hp,
    StatKey.atk,
    StatKey.def,
    StatKey.em,
    StatKey.critRate,
    StatKey.critDmg,
    StatKey.er,
    StatKey.elemDmg,
    StatKey.physDmg,
  ];
  const optionalKeys = [
    StatKey.healing,
    StatKey.incomingHealing,
    StatKey.shield,
  ];

  final rows = <StatDeltaRow>[];
  for (final key in mainKeys) {
    rows.add(
      StatDeltaRow(
        key: key,
        label: key == StatKey.elemDmg ? elementLabel : statLabels[key]!,
        current: current[key] ?? 0,
        simulated: simulated[key] ?? 0,
      ),
    );
  }
  for (final key in optionalKeys) {
    final c = current[key] ?? 0;
    final s = simulated[key] ?? 0;
    if (c != 0 || s != 0) {
      rows.add(
        StatDeltaRow(
          key: key,
          label: statLabels[key]!,
          current: c,
          simulated: s,
        ),
      );
    }
  }
  return rows;
}

String formatStatValue(StatKey key, double value) {
  if (percentStatKeys.contains(key)) {
    return '${value.toStringAsFixed(1)}%';
  }
  return value.round().toString();
}

String formatStatDelta(StatKey key, double delta) {
  final sign = delta >= 0 ? '+' : '';
  if (percentStatKeys.contains(key)) {
    return '$sign${delta.toStringAsFixed(1)}%';
  }
  return '$sign${delta.round()}';
}
