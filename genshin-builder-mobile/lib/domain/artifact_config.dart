import 'models/artifact_state.dart';

const artifactSlotLabels = {
  ArtifactSlotKey.flower: '花',
  ArtifactSlotKey.plume: '羽',
  ArtifactSlotKey.sands: '時計',
  ArtifactSlotKey.goblet: '杯',
  ArtifactSlotKey.circlet: '冠',
};

const artifactSlotOrder = [
  ArtifactSlotKey.flower,
  ArtifactSlotKey.plume,
  ArtifactSlotKey.sands,
  ArtifactSlotKey.goblet,
  ArtifactSlotKey.circlet,
];

const mainStatOptions = {
  ArtifactSlotKey.flower: ['HP'],
  ArtifactSlotKey.plume: ['攻撃力'],
  ArtifactSlotKey.sands: [
    'HP%',
    '攻撃力%',
    '防御力%',
    '元素熟知',
    '元素チャージ効率',
  ],
  ArtifactSlotKey.goblet: [
    'HP%',
    '攻撃力%',
    '防御力%',
    '元素熟知',
    '炎元素ダメージ',
    '水元素ダメージ',
    '雷元素ダメージ',
    '氷元素ダメージ',
    '風元素ダメージ',
    '岩元素ダメージ',
    '草元素ダメージ',
    '物理ダメージ',
  ],
  ArtifactSlotKey.circlet: [
    'HP%',
    '攻撃力%',
    '防御力%',
    '元素熟知',
    '会心率',
    '会心ダメージ',
    '与える治療効果',
  ],
};

const subStatOptions = [
  '会心率',
  '会心ダメージ',
  '攻撃力%',
  '攻撃力',
  'HP%',
  'HP',
  '防御力%',
  '防御力',
  '元素熟知',
  '元素チャージ効率',
];

/// HoYoLAB の部位名 → スロット
ArtifactSlotKey? artifactSlotFromPosName(String posName) {
  if (posName.contains('花')) return ArtifactSlotKey.flower;
  if (posName.contains('羽')) return ArtifactSlotKey.plume;
  if (posName.contains('砂') || posName.contains('時計')) {
    return ArtifactSlotKey.sands;
  }
  if (posName.contains('杯')) return ArtifactSlotKey.goblet;
  if (posName.contains('冠')) return ArtifactSlotKey.circlet;
  return null;
}

String buildArtifactSummary(ArtifactState artifacts) {
  final setCounts = <String, int>{};
  for (final piece in artifacts.values) {
    if (piece.setName.isNotEmpty) {
      setCounts[piece.setName] = (setCounts[piece.setName] ?? 0) + 1;
    }
  }

  final setParts = setCounts.entries
      .where((e) => e.value >= 2)
      .map((e) {
        final count = e.value >= 4 ? 4 : 2;
        return '${e.key} ×$count';
      })
      .toList();

  final levelParts = artifactSlotOrder
      .map((slot) {
        final label = artifactSlotLabels[slot]!;
        return '$label+${artifacts[slot]?.level ?? 0}';
      })
      .join(' · ');

  if (setParts.isEmpty) {
    return levelParts;
  }
  return '${setParts.join(' / ')} · $levelParts';
}
