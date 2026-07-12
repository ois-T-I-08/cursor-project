/// Project Amber API 定数・マッピング（Web `project-amber.ts` 相当）
library;

export '../../domain/game_display.dart';

const amberBaseUrl = 'https://gi.yatta.moe';
const amberAssetUrl = '$amberBaseUrl/assets/UI';

const elementMap = <String, String>{
  'Fire': 'pyro',
  'Water': 'hydro',
  'Electric': 'electro',
  'Ice': 'cryo',
  'Wind': 'anemo',
  'Rock': 'geo',
  'Grass': 'dendro',
};

const weaponTypeMap = <String, String>{
  'WEAPON_SWORD_ONE_HAND': 'sword',
  'WEAPON_CLAYMORE': 'claymore',
  'WEAPON_POLE': 'polearm',
  'WEAPON_BOW': 'bow',
  'WEAPON_CATALYST': 'catalyst',
};

const regionMap = <String, String>{
  'MONDSTADT': 'モンド',
  'LIYUE': '璃月',
  'INAZUMA': '稲妻',
  'SUMERU': 'スメール',
  'FONTAINE': 'フォンテーヌ',
  'NATLAN': 'ナタ',
  'NODKRAI': 'ノド・クライ',
  'FATUI': 'ファデュイ',
  'MAINACTOR': '旅人',
};

const materialCategories = {
  'characterLevelUpMaterial',
  'characterAscensionMaterial',
  'characterTalentMaterial',
  'characterEXPMaterial',
  'characterandWeaponEnhancementMaterial',
  'weaponAscensionMaterial',
  'weaponEnhancementMaterial',
  'localSpecialtyMondstadt',
  'localSpecialtyLiyue',
  'localSpecialtyInazuma',
  'localSpecialtySumeru',
  'localSpecialtyFontaine',
  'localSpecialtyNatlan',
  'localSpecialtyNodKrai',
};

String buildIconUrl(String icon) {
  if (icon.isEmpty) return '';
  // 聖遺物アイコンのみ assets/UI/reliquary/ 配下
  if (icon.startsWith('UI_RelicIcon_')) {
    return '$amberAssetUrl/reliquary/$icon.png';
  }
  return '$amberAssetUrl/$icon.png';
}

/// Amber sortOrder と既知例外から聖遺物セットの地域を推定する。
/// API に region が無いため、新規セットは sortOrder 帯で自動分類する。
String resolveArtifactSetRegion({
  required String id,
  required int sortOrder,
}) {
  const idOverrides = <String, String>{
    // 層岩巨淵（sortOrder が稲妻帯だが璃月）
    '15023': '璃月',
    '15024': '璃月',
  };
  final overridden = idOverrides[id];
  if (overridden != null) return overridden;

  if (sortOrder <= 48) return 'モンド';
  if (sortOrder <= 69) return '璃月';
  if (sortOrder <= 81) return '稲妻';
  if (sortOrder <= 89) return 'スメール';
  if (sortOrder <= 101) return 'フォンテーヌ';
  if (sortOrder <= 109) return 'ナタ';
  if (sortOrder <= 200) return 'ノド・クライ';
  return 'その他';
}

/// 聖遺物一覧の地域セクション表示順（[gameRegionDisplayOrder] と同期）
const artifactSetRegionOrder = <String>[
  'モンド',
  '璃月',
  '稲妻',
  'スメール',
  'フォンテーヌ',
  'ナタ',
  'ノド・クライ',
  'その他',
];
