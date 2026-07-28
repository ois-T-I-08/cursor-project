/// キャラ別の聖遺物セット使用率（Akasha 公開ビルド集計）
class CharacterArtifactSetUsageSnapshot {
  const CharacterArtifactSetUsageSnapshot({
    required this.characterId,
    required this.rates,
    required this.sampleSize,
    required this.source,
    required this.fetchedAt,
  });

  final String characterId;

  /// 英語セット名（Akasha / Enka route）→ 使用率 0〜1
  final Map<String, double> rates;

  final int sampleSize;
  final String source;
  final DateTime fetchedAt;

  bool get isFromRemote => source.startsWith('akasha');

  double rateFor(String setKey) => rates[setKey] ?? 0;
}

/// ビルド一覧から「2部位以上」のセット出現回数を集計する。
Map<String, int> countArtifactSetsFromBuilds(
  List<dynamic> builds, {
  int minPieces = 2,
}) {
  final counts = <String, int>{};
  for (final raw in builds) {
    if (raw is! Map) continue;
    final sets = raw['artifactSets'];
    if (sets is! Map) continue;
    for (final entry in sets.entries) {
      final name = '${entry.key}'.trim();
      if (name.isEmpty) continue;
      final value = entry.value;
      var pieceCount = 0;
      if (value is Map) {
        pieceCount = (value['count'] as num?)?.toInt() ?? 0;
      } else if (value is num) {
        pieceCount = value.toInt();
      }
      if (pieceCount < minPieces) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return counts;
}

Map<String, double> artifactSetRatesFromCounts(
  Map<String, int> counts,
  int sampleSize,
) {
  if (sampleSize <= 0) return const {};
  return {for (final e in counts.entries) e.key: e.value / sampleSize};
}
