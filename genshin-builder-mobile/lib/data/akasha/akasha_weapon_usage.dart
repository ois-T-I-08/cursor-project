/// キャラ別の武器使用率スナップショット（Akasha 公開ビルド集計）
class WeaponUsageSnapshot {
  const WeaponUsageSnapshot({
    required this.characterId,
    required this.rates,
    required this.sampleSize,
    required this.source,
    required this.fetchedAt,
  });

  /// Amber / ゲーム共通のキャラ ID（例: `10000046`）
  final String characterId;

  /// weaponId → 使用率（0.0〜1.0）
  final Map<String, double> rates;

  /// 集計に使ったビルド件数
  final int sampleSize;

  /// データ取得元ラベル（例: `akasha.cv` / `heuristic`）
  final String source;

  final DateTime fetchedAt;

  bool get isFromRemote => source.startsWith('akasha');

  double rateFor(String weaponId) => rates[weaponId] ?? 0;

  /// 使用率をソート用スコアへ（0〜1000 程度 + タイブレーク余地）
  double scoreFor(String weaponId) => rateFor(weaponId) * 1000;
}

/// Akasha builds レスポンスから武器出現回数を集計する純関数（テスト用）
Map<String, int> countWeaponIdsFromBuilds(List<dynamic> builds) {
  final counts = <String, int>{};
  for (final raw in builds) {
    if (raw is! Map) continue;
    final weapon = raw['weapon'];
    if (weapon is! Map) continue;
    final id = weapon['weaponId'];
    if (id == null) continue;
    final key = '$id';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// 出現回数 → 使用率（合計 0 のときは空）
Map<String, double> ratesFromCounts(Map<String, int> counts) {
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return const {};
  return {for (final e in counts.entries) e.key: e.value / total};
}
