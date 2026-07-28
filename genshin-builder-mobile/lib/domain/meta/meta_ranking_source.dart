/// メタ・ランキングデータソースの抽象（Akasha / 独自DB 等）。
library;

/// 汎用ランキング行
class MetaRankingEntry {
  const MetaRankingEntry({
    required this.entityId,
    required this.score,
    this.label,
    this.sampleSize = 0,
  });

  final String entityId;
  final double score;
  final String? label;
  final int sampleSize;
}

class MetaRankingSnapshot {
  const MetaRankingSnapshot({
    required this.contextId,
    required this.entries,
    required this.source,
    required this.fetchedAt,
    this.sampleSize = 0,
  });

  /// 例: キャラ ID（武器使用率ランキングの文脈）
  final String contextId;
  final List<MetaRankingEntry> entries;
  final String source;
  final DateTime fetchedAt;
  final int sampleSize;

  Map<String, double> get scoresById => {
    for (final e in entries) e.entityId: e.score,
  };
}

/// ランキング取得ポート
abstract class MetaRankingSource {
  /// [kind] 例: `weapon_usage`
  Future<MetaRankingSnapshot> fetchRanking({
    required String kind,
    required String contextId,
  });
}
