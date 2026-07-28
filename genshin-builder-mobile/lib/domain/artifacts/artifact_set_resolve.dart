import '../models/amber_detail_models.dart';
import '../models/artifact_state.dart';
import '../models/master_models.dart';
import 'artifact_set_recommendations.dart';

/// `UI_RelicIcon_15020_4` / URL から聖遺物セット ID を取り出す。
String? extractReliquarySetIdFromIcon(String? iconOrUrl) {
  if (iconOrUrl == null || iconOrUrl.isEmpty) return null;
  final match = RegExp(
    r'UI_RelicIcon_(\d+)',
    caseSensitive: false,
  ).firstMatch(iconOrUrl);
  return match?.group(1);
}

/// Amber セット一覧から名前・route・ID で解決するカタログ。
class ArtifactSetCatalog {
  ArtifactSetCatalog._({
    required this.byId,
    required this.byNameKey,
    required this.byRouteKey,
  });

  factory ArtifactSetCatalog.fromSets(
    List<ArtifactSetDetail> sets, {
    Map<String, String> aliases = const {},
  }) {
    final byId = <String, ArtifactSetDetail>{};
    final byNameKey = <String, ArtifactSetDetail>{};
    final byRouteKey = <String, ArtifactSetDetail>{};
    for (final set in sets) {
      byId[set.id] = set;
      byNameKey[normalizeArtifactSetKey(set.name)] = set;
      if (set.route.isNotEmpty) {
        byRouteKey[normalizeArtifactSetKey(set.route)] = set;
      }
    }

    // aliases: 表記ゆれ → 正規セット名（または route）
    for (final e in aliases.entries) {
      final targetKey = normalizeArtifactSetKey(e.value);
      final target =
          byNameKey[targetKey] ?? byRouteKey[targetKey] ?? byId[e.value.trim()];
      if (target == null) continue;
      byNameKey[normalizeArtifactSetKey(e.key)] = target;
    }

    return ArtifactSetCatalog._(
      byId: byId,
      byNameKey: byNameKey,
      byRouteKey: byRouteKey,
    );
  }

  final Map<String, ArtifactSetDetail> byId;
  final Map<String, ArtifactSetDetail> byNameKey;
  final Map<String, ArtifactSetDetail> byRouteKey;

  /// アイコン ID を最優先。次にセット名 / route（言語差・エイリアスを吸収）。
  ArtifactSetDetail? resolvePiece(ArtifactPiece piece) {
    final fromIcon = extractReliquarySetIdFromIcon(piece.iconUrl);
    if (fromIcon != null) {
      final byIcon = byId[fromIcon];
      if (byIcon != null) return byIcon;
    }

    final raw = piece.setName.trim();
    if (raw.isEmpty) return null;
    final key = normalizeArtifactSetKey(raw);
    return byNameKey[key] ?? byRouteKey[key] ?? byId[raw];
  }
}

/// 進捗の各部位をセット ID ごとに集計（解決できない部位は無視）。
Map<String, int> countEquippedSetsById(
  UserProgress progress,
  ArtifactSetCatalog catalog,
) {
  return countEquippedSetsFromPieces(progress.artifacts.values, catalog);
}

/// 任意の部位リストをセット ID ごとに集計。
Map<String, int> countEquippedSetsFromPieces(
  Iterable<ArtifactPiece> pieces,
  ArtifactSetCatalog catalog,
) {
  final counts = <String, int>{};
  for (final piece in pieces) {
    final set = catalog.resolvePiece(piece);
    if (set == null) continue;
    counts[set.id] = (counts[set.id] ?? 0) + 1;
  }
  return counts;
}
