import '../models/amber_detail_models.dart';
import 'artifact_set_recommendations.dart';
import 'artifact_set_resolve.dart';

/// キャラ詳細向けおすすめ聖遺物セット1件。
class CharacterRecommendedArtifactSet {
  const CharacterRecommendedArtifactSet({
    required this.set,
    this.usageRate,
    this.source = 'config',
  });

  final ArtifactSetDetail set;
  final double? usageRate;
  final String source;

  bool get isFromAkasha => source == 'akasha';
}

/// Akasha 使用率を優先し、不足分を設定 JSON から補完する。
List<CharacterRecommendedArtifactSet> buildCharacterRecommendedArtifactSets({
  required String characterId,
  required String characterName,
  required List<ArtifactSetDetail> sets,
  Map<String, double> akashaRates = const {},
  Map<String, List<String>> configRecommendationsBySetName = const {},
  Map<String, String> setNameAliases = const {},
  double minRate = 0.05,
  int maxRecommended = 6,
}) {
  final catalog = ArtifactSetCatalog.fromSets(sets, aliases: setNameAliases);
  final recommended = <CharacterRecommendedArtifactSet>[];
  final seen = <String>{};

  final sorted =
      akashaRates.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    if (recommended.length >= maxRecommended) break;
    if (e.value < minRate) continue;
    final key = normalizeArtifactSetKey(e.key);
    final set = catalog.byRouteKey[key] ?? catalog.byNameKey[key];
    if (set == null || !seen.add(set.id)) continue;
    recommended.add(
      CharacterRecommendedArtifactSet(
        set: set,
        usageRate: e.value,
        source: 'akasha',
      ),
    );
  }

  if (recommended.length < maxRecommended) {
    bool matchesCharacter(String token) {
      final t = token.trim();
      return t == characterId || t == characterName;
    }

    for (final set in sets) {
      if (recommended.length >= maxRecommended) break;
      if (seen.contains(set.id)) continue;

      final configNames = <String>[
        ...?configRecommendationsBySetName[set.name],
        for (final e in setNameAliases.entries)
          if (e.value == set.name ||
              normalizeArtifactSetKey(e.value) ==
                  normalizeArtifactSetKey(set.name))
            ...?configRecommendationsBySetName[e.key],
      ];
      if (!configNames.any(matchesCharacter)) continue;
      seen.add(set.id);
      recommended.add(
        CharacterRecommendedArtifactSet(set: set, source: 'config'),
      );
    }
  }

  return recommended;
}
