/// 育成プラン系 UI 向けの日本語ラベル（内部キーは英語のまま維持）。
library;

/// UpgradeOption.optionType / GrowthRouteAction.reasons 用
String growthOptionTypeLabel(String optionType) {
  return switch (optionType) {
    'level' => 'キャラレベル',
    'talentNormal' => '通常攻撃',
    'talentSkill' => '元素スキル',
    'talentBurst' => '元素爆発',
    'weapon' => '武器レベル',
    'artifact' => '聖遺物',
    _ => optionType,
  };
}

/// GrowthRouteAction.actionType 用
String growthActionTypeLabel(String actionType) {
  return switch (actionType) {
    'weekdayMaterial' => '曜日限定素材',
    'generalMaterial' => '通常素材',
    'mora' => 'モラ',
    'expBook' => '経験値本',
    'boss' => 'ボス素材',
    _ => actionType,
  };
}

/// `{goalUuid}_talentNormal` 形式から optionType を取り出す。
String? growthOptionTypeFromOptionId(String optionId) {
  const suffixes = <String>[
    'talentNormal',
    'talentSkill',
    'talentBurst',
    'weapon',
    'artifact',
    'level',
  ];
  for (final s in suffixes) {
    if (optionId.endsWith('_$s')) return s;
  }
  return null;
}
