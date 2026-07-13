/// UI 表示用ラベル・色（features は data/amber ではなくここを参照する）
library;

const elementLabelMap = <String, String>{
  'pyro': '炎',
  'hydro': '水',
  'electro': '雷',
  'cryo': '氷',
  'anemo': '風',
  'geo': '岩',
  'dendro': '草',
};

const weaponTypeLabelMap = <String, String>{
  'sword': '片手剣',
  'claymore': '両手剣',
  'polearm': '長柄武器',
  'bow': '弓',
  'catalyst': '法器',
};

/// 元素バッジ用カラー（Web `ELEMENT_INFO` 相当）
const elementColorMap = <String, int>{
  'pyro': 0xFFFF6B4A,
  'hydro': 0xFF4FC3F7,
  'electro': 0xFFB388FF,
  'cryo': 0xFF80DEEA,
  'anemo': 0xFF69F0AE,
  'geo': 0xFFFFD54F,
  'dendro': 0xFFA5D6A7,
};

/// 地域セクションの表示順（聖遺物一覧実装時と同じ）
const gameRegionDisplayOrder = <String>[
  'モンド',
  '璃月',
  '稲妻',
  'スメール',
  'フォンテーヌ',
  'ナタ',
  'ノド・クライ',
  'その他',
];

/// Amber / DB の地域を一覧セクション用に正規化する。
/// ファデュイ・旅人はセクションに出さず、例外キャラは指定地域へ寄せる。
String normalizeCharacterRegionForDisplay(
  String region, {
  String? characterId,
  String? characterName,
}) {
  final id = characterId?.trim() ?? '';
  final name = characterName?.trim() ?? '';

  // ID 優先（同期後も安定）
  const idOverrides = <String, String>{
    // スカーク → ナタ
    '10000114': 'ナタ',
    // タルタリヤ → 璃月
    '10000033': '璃月',
    // アルレッキーノ → フォンテーヌ
    '10000096': 'フォンテーヌ',
    // サンドローネ（ID 確定済み）
  };
  final byId = idOverrides[id];
  if (byId != null) return byId;

  // 名前（表記ゆれ・未登録 ID 向け）
  if (name == 'スカーク' || name.toLowerCase() == 'skirk') {
    return 'ナタ';
  }
  if (name == 'サンドローネ' ||
      name.toLowerCase() == 'sandrone' ||
      name.contains('サンドローネ')) {
    return 'ノド・クライ';
  }
  // 未登録 ID のニコ（ニコ・リヤン）→ ノド・クライ
  if (name.contains('ニコ') ||
      name.toLowerCase() == 'nico' ||
      name.toLowerCase() == 'nico·liyue' ||
      name.toLowerCase() == 'nico liyue') {
    return 'ノド・クライ';
  }
  // 未登録 ID の兹白（しはく）→ ノド・クライ
  if (name.contains('兹白') ||
      name.contains('茲白') ||
      name == 'しはく' ||
      name.toLowerCase() == 'shihaku' ||
      name.toLowerCase() == 'zihai') {
    return 'ノド・クライ';
  }

  final raw = region.trim();
  if (raw.isEmpty) return 'その他';

  // ファデュイ / 旅人は独立セクションにしない
  if (raw == 'ファデュイ' || raw == 'FATUI') return 'その他';
  if (raw == '旅人' || raw == 'MAINACTOR') return 'その他';

  return raw;
}

int gameRegionSortIndex(String region) {
  final i = gameRegionDisplayOrder.indexOf(region);
  return i < 0 ? gameRegionDisplayOrder.length : i;
}
