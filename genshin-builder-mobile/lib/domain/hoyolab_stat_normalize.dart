import 'artifact_config.dart';
import 'models/artifact_state.dart';

/// HoYoLAB / property_map の表示名をアプリ内ラベルへ正規化
String? normalizeMainStatForSlot(String apiLabel, ArtifactSlotKey slot) {
  return _normalizeStatLabel(apiLabel, mainStatOptions[slot] ?? const []);
}

String? normalizeSubStatLabel(String apiLabel) {
  return _normalizeStatLabel(apiLabel, subStatOptions);
}

String? _normalizeStatLabel(String apiLabel, List<String> options) {
  final cleaned = apiLabel.replaceAll('\u00a0', ' ').trim();
  if (cleaned.isEmpty) return null;
  if (options.contains(cleaned)) return cleaned;

  for (final option in options) {
    if (_labelsMatch(cleaned, option)) return option;
  }

  final alias = _aliasToAppLabel(cleaned);
  if (alias != null) {
    if (options.contains(alias)) return alias;
    for (final option in options) {
      if (_labelsMatch(alias, option)) return option;
    }
  }

  return null;
}

bool _labelsMatch(String a, String b) {
  if (a == b) return true;
  final na = _normalizeKey(a);
  final nb = _normalizeKey(b);
  return na == nb || na.contains(nb) || nb.contains(na);
}

String _normalizeKey(String value) {
  return value
      .replaceAll('%', '')
      .replaceAll(' ', '')
      .replaceAll('％', '')
      .toLowerCase();
}

String? _aliasToAppLabel(String label) {
  const aliases = {
    '生命值': 'HP',
    '生命': 'HP',
    'hp': 'HP',
    '攻击力': '攻撃力',
    '攻撃': '攻撃力',
    'attack': '攻撃力',
    '防御力': '防御力',
    '防御': '防御力',
    'defense': '防御力',
    '生命值%': 'HP%',
    'hp%': 'HP%',
    'life%': 'HP%',
    '攻击力%': '攻撃力%',
    '攻撃力%': '攻撃力%',
    'attack%': '攻撃力%',
    '防御力%': '防御力%',
    'defense%': '防御力%',
    '元素精通': '元素熟知',
    '元素熟知': '元素熟知',
    'elementalmastery': '元素熟知',
    '元素充能效率': '元素チャージ効率',
    '元素チャージ': '元素チャージ効率',
    'energyrecharge': '元素チャージ効率',
    '暴击率': '会心率',
    '会心率': '会心率',
    'critrate': '会心率',
    '暴击伤害': '会心ダメージ',
    '会心ダメージ': '会心ダメージ',
    'critdamage': '会心ダメージ',
    '治疗加成': '与える治療効果',
    '与える治療効果': '与える治療効果',
    'healingbonus': '与える治療効果',
    '火元素伤害加成': '炎元素ダメージ',
    '火元素ダメージ': '炎元素ダメージ',
    '炎元素ダメージ': '炎元素ダメージ',
    'pyrodamage': '炎元素ダメージ',
    '水元素伤害加成': '水元素ダメージ',
    '水元素ダメージ': '水元素ダメージ',
    'hydrodamage': '水元素ダメージ',
    '雷元素伤害加成': '雷元素ダメージ',
    '雷元素ダメージ': '雷元素ダメージ',
    'electrodamage': '雷元素ダメージ',
    '冰元素伤害加成': '氷元素ダメージ',
    '氷元素ダメージ': '氷元素ダメージ',
    'cryodamage': '氷元素ダメージ',
    '风元素伤害加成': '風元素ダメージ',
    '風元素ダメージ': '風元素ダメージ',
    'anemodamage': '風元素ダメージ',
    '岩元素伤害加成': '岩元素ダメージ',
    '岩元素ダメージ': '岩元素ダメージ',
    'geodamage': '岩元素ダメージ',
    '草元素伤害加成': '草元素ダメージ',
    '草元素ダメージ': '草元素ダメージ',
    'dendrodamage': '草元素ダメージ',
    '物理伤害加成': '物理ダメージ',
    '物理ダメージ': '物理ダメージ',
    'physicaldamage': '物理ダメージ',
  };

  final direct = aliases[label] ?? aliases[_normalizeKey(label)];
  if (direct != null) return direct;

  for (final entry in aliases.entries) {
    if (label.contains(entry.key) || entry.key.contains(label)) {
      return entry.value;
    }
  }
  return null;
}

/// filter_name（FIGHT_PROP_*）→ アプリ内ラベル
String? labelFromFilterName(String? filterName) {
  if (filterName == null || filterName.isEmpty) return null;
  return switch (filterName) {
    'FIGHT_PROP_HP' ||
    'FIGHT_PROP_BASE_HP' =>
      'HP',
    'FIGHT_PROP_HP_PERCENT' => 'HP%',
    'FIGHT_PROP_ATTACK' ||
    'FIGHT_PROP_BASE_ATTACK' =>
      '攻撃力',
    'FIGHT_PROP_ATTACK_PERCENT' => '攻撃力%',
    'FIGHT_PROP_DEFENSE' ||
    'FIGHT_PROP_BASE_DEFENSE' =>
      '防御力',
    'FIGHT_PROP_DEFENSE_PERCENT' => '防御力%',
    'FIGHT_PROP_ELEMENT_MASTERY' => '元素熟知',
    'FIGHT_PROP_CRITICAL' => '会心率',
    'FIGHT_PROP_CRITICAL_HURT' => '会心ダメージ',
    'FIGHT_PROP_CHARGE_EFFICIENCY' => '元素チャージ効率',
    'FIGHT_PROP_HEAL_ADD' => '与える治療効果',
    'FIGHT_PROP_HEALED_ADD' => '受ける治療効果',
    'FIGHT_PROP_PHYSICAL_ADD_HURT' => '物理ダメージ',
    'FIGHT_PROP_FIRE_ADD_HURT' => '炎元素ダメージ',
    'FIGHT_PROP_WATER_ADD_HURT' => '水元素ダメージ',
    'FIGHT_PROP_ELECTRIC_ADD_HURT' => '雷元素ダメージ',
    'FIGHT_PROP_ICE_ADD_HURT' => '氷元素ダメージ',
    'FIGHT_PROP_WIND_ADD_HURT' => '風元素ダメージ',
    'FIGHT_PROP_ROCK_ADD_HURT' => '岩元素ダメージ',
    'FIGHT_PROP_GRASS_ADD_HURT' => '草元素ダメージ',
    _ => null,
  };
}
