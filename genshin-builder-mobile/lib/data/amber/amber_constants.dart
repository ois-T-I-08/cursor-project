/// Project Amber API 定数・マッピング（Web `project-amber.ts` 相当）
library;

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

const elementLabelMap = <String, String>{
  'pyro': '炎',
  'hydro': '水',
  'electro': '雷',
  'cryo': '氷',
  'anemo': '風',
  'geo': '岩',
  'dendro': '草',
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

String buildIconUrl(String icon) => '$amberAssetUrl/$icon.png';
