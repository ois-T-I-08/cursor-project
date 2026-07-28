/// セット別おすすめ1件（キャラ ID + 使用率）
class ArtifactSetRecommendationHit {
  const ArtifactSetRecommendationHit({
    required this.characterId,
    required this.usageRate,
    required this.source,
  });

  final String characterId;
  final double usageRate;
  final String source;
}

/// 英語セット名 → おすすめキャラ（使用率降順）
typedef ArtifactSetRecommendationIndex =
    Map<String, List<ArtifactSetRecommendationHit>>;

String normalizeArtifactSetKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// キャラ別使用率をセット別ランキングへ反転する。
ArtifactSetRecommendationIndex invertCharacterSetUsage({
  required Iterable<
    ({String characterId, Map<String, double> rates, bool isRemote})
  >
  snapshots,
  double minRate = 0.05,
  int topPerSet = 8,
}) {
  final buckets = <String, List<ArtifactSetRecommendationHit>>{};
  for (final snap in snapshots) {
    if (!snap.isRemote) continue;
    for (final e in snap.rates.entries) {
      if (e.value < minRate) continue;
      buckets
          .putIfAbsent(e.key, () => [])
          .add(
            ArtifactSetRecommendationHit(
              characterId: snap.characterId,
              usageRate: e.value,
              source: 'akasha',
            ),
          );
    }
  }
  for (final list in buckets.values) {
    list.sort((a, b) => b.usageRate.compareTo(a.usageRate));
    if (list.length > topPerSet) {
      list.removeRange(topPerSet, list.length);
    }
  }
  return buckets;
}
