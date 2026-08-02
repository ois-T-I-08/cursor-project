/// Amber 詳細の正規化モデル（UI / domain 共有。HTTP 非依存）
library;

import '../character_stats.dart';

/// スキルのレベル別数値 1 行（例: 「1段ダメージ」「クールタイム」）
class TalentStatRow {
  const TalentStatRow({required this.label, required this.value});

  final String label;
  final String value;
}

/// スキル種別（通常攻撃 / 元素スキル / 元素爆発 / 固有天賦）
enum TalentDetailKind { normal, skill, burst, passive }

const talentDetailKindLabels = <TalentDetailKind, String>{
  TalentDetailKind.normal: '通常攻撃',
  TalentDetailKind.skill: '元素スキル',
  TalentDetailKind.burst: '元素爆発',
  TalentDetailKind.passive: '固有天賦',
};

class TalentDetailData {
  const TalentDetailData({
    required this.kind,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.levelStats,
  });

  final TalentDetailKind kind;
  final String name;
  final String description;
  final String? iconUrl;

  /// レベル → 数値行（倍率・CT・元素エネルギー等）。パッシブは空
  final Map<int, List<TalentStatRow>> levelStats;

  int get maxStatLevel =>
      levelStats.keys.isEmpty
          ? 0
          : levelStats.keys.reduce((a, b) => a > b ? a : b);
}

class AvatarDetailData {
  const AvatarDetailData({
    required this.talents,
    required this.stats,
    this.constellations = const [],
  });

  final List<TalentDetailData> talents;

  /// ステータス計算用（曲線取得失敗時は null）
  final AvatarStatsData? stats;

  /// 命ノ星座 第1〜6重（取得失敗時は空）
  final List<ConstellationDetailData> constellations;

  List<TalentDetailData> get activeTalents =>
      talents.where((t) => t.kind != TalentDetailKind.passive).toList();

  List<TalentDetailData> get passiveTalents =>
      talents.where((t) => t.kind == TalentDetailKind.passive).toList();
}

/// 命ノ星座 1 段階分
class ConstellationDetailData {
  const ConstellationDetailData({
    required this.position,
    required this.name,
    required this.description,
    this.iconUrl,
  });

  /// 1〜6
  final int position;
  final String name;
  final String description;
  final String? iconUrl;
}

/// 武器詳細（長押し表示・精錬効果付き）
class WeaponDetailData {
  const WeaponDetailData({
    required this.id,
    required this.name,
    required this.rarity,
    required this.weaponType,
    required this.weaponTypeLabel,
    required this.iconUrl,
    required this.stats,
    required this.subStatProp,
    required this.subStatName,
    required this.effectName,
    required this.effectDescriptions,
  });

  final String id;
  final String name;
  final int rarity;
  final String weaponType;
  final String weaponTypeLabel;
  final String? iconUrl;
  final WeaponStatsData stats;
  final String? subStatProp;
  final String? subStatName;

  /// 武器効果名（精錬パッシブ）
  final String? effectName;

  /// R1〜R5 の効果説明（index 0 = R1）
  final List<String> effectDescriptions;
}

/// 聖遺物セット効果
class ArtifactSetDetail {
  const ArtifactSetDetail({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.effects,
    this.region = 'その他',
    this.sortOrder = 0,
    this.route = '',
  });

  final String id;
  final String name;
  final String? iconUrl;

  /// 2セット / 4セット効果テキスト
  final List<String> effects;

  /// 表示用地域（モンド / 璃月 / …）
  final String region;

  final int sortOrder;

  /// Amber / Enka 英語ルート名（Akasha `artifactSets` キーと突合）
  final String route;
}
