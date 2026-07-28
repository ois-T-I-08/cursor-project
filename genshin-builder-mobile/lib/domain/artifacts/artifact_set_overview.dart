import '../models/amber_detail_models.dart';
import '../models/artifact_state.dart';
import '../models/master_models.dart';
import 'artifact_set_recommendations.dart';
import 'artifact_set_resolve.dart';

export 'artifact_set_recommendations.dart';
export 'artifact_set_resolve.dart';

/// 聖遺物セット一覧1行分（APIセット + ユーザー装備 + 推奨）。
class ArtifactSetOverview {
  const ArtifactSetOverview({
    required this.set,
    required this.equippedCharacters,
    required this.recommendedCharacters,
  });

  final ArtifactSetDetail set;
  final List<ArtifactEquippedCharacter> equippedCharacters;
  final List<ArtifactSetRecommendedCharacter> recommendedCharacters;

  String get twoPieceEffect => set.effects.isNotEmpty ? set.effects[0] : '';

  String get fourPieceEffect => set.effects.length > 1 ? set.effects[1] : '';
}

/// おすすめキャラ（Akasha 使用率 or 設定フォールバック）
class ArtifactSetRecommendedCharacter {
  const ArtifactSetRecommendedCharacter({
    required this.character,
    this.usageRate,
    this.source = 'config',
  });

  final MasterCharacter character;
  final double? usageRate;
  final String source;

  bool get isFromAkasha => source == 'akasha';
}

/// 装備中のセット1種（件数・アイコン）。
class ArtifactSetPieceCount {
  const ArtifactSetPieceCount({
    required this.setName,
    required this.count,
    this.iconUrl,
  });

  final String setName;
  final int count;
  final String? iconUrl;
}

class ArtifactEquippedCharacter {
  const ArtifactEquippedCharacter({
    required this.character,
    required this.artifactCompleted,
    required this.isOwned,
    required this.targetSetPieceCount,
    required this.companionSets,
  });

  final MasterCharacter character;
  final bool artifactCompleted;
  final bool isOwned;

  /// 対象セットの装備部位数（2以上で一覧に載る）
  final int targetSetPieceCount;

  /// 2セット表示時に周囲へ出すセット（対象＋他セット）。4セット時は空。
  final List<ArtifactSetPieceCount> companionSets;

  bool get isFourSet => targetSetPieceCount >= 4;

  bool get isTwoSet => targetSetPieceCount >= 2 && targetSetPieceCount < 4;

  int get equippedPieceCount => targetSetPieceCount;
}

/// 装備集計の1キャラ分入力（HoYoLAB 聖遺物 or 進捗 JSON）。
class ArtifactEquipInput {
  const ArtifactEquipInput({
    required this.characterId,
    required this.pieces,
    this.artifactCompleted = false,
  });

  final String characterId;
  final Iterable<ArtifactPiece> pieces;
  final bool artifactCompleted;
}

/// [UserProgress] 一覧から装備入力を作る（後方互換・テスト用）。
List<ArtifactEquipInput> artifactEquipInputsFromProgress(
  List<UserProgress> progressList,
) {
  return [
    for (final p in progressList)
      ArtifactEquipInput(
        characterId: p.characterId,
        pieces: p.artifacts.values,
        artifactCompleted: p.artifactCompleted,
      ),
  ];
}

/// セット ID ごとの装備キャラを集計する。
/// 対象セットが **2部位未満** のキャラは載せない。
/// 部位のセット解決はアイコン ID → 名前 / route の順（言語差に強い）。
Map<String, List<ArtifactEquippedCharacter>> groupEquippedBySetId({
  required List<ArtifactEquipInput> inputs,
  required Map<String, MasterCharacter> charactersById,
  required Set<String> ownedCharacterIds,
  required ArtifactSetCatalog catalog,
}) {
  final result = <String, List<ArtifactEquippedCharacter>>{};

  for (final input in inputs) {
    final character = charactersById[input.characterId];
    if (character == null) continue;

    final counts = countEquippedSetsFromPieces(input.pieces, catalog);
    if (counts.isEmpty) continue;

    final isOwned = ownedCharacterIds.contains(input.characterId);
    for (final entry in counts.entries) {
      final targetCount = entry.value;
      if (targetCount < 2) continue;

      final targetSet = catalog.byId[entry.key];
      if (targetSet == null) continue;

      final companions = <ArtifactSetPieceCount>[];
      if (targetCount < 4) {
        companions.add(
          ArtifactSetPieceCount(
            setName: targetSet.name,
            count: targetCount,
            iconUrl: targetSet.iconUrl,
          ),
        );
        final others =
            counts.entries
                .where((e) => e.key != entry.key && e.value > 0)
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
        for (final other in others) {
          final otherSet = catalog.byId[other.key];
          if (otherSet == null) continue;
          companions.add(
            ArtifactSetPieceCount(
              setName: otherSet.name,
              count: other.value,
              iconUrl: otherSet.iconUrl,
            ),
          );
        }
      }

      result
          .putIfAbsent(entry.key, () => [])
          .add(
            ArtifactEquippedCharacter(
              character: character,
              artifactCompleted: input.artifactCompleted,
              isOwned: isOwned,
              targetSetPieceCount: targetCount,
              companionSets: companions,
            ),
          );
    }
  }

  for (final list in result.values) {
    list.sort((a, b) {
      if (a.isOwned != b.isOwned) return a.isOwned ? -1 : 1;
      if (a.isFourSet != b.isFourSet) return a.isFourSet ? -1 : 1;
      if (a.artifactCompleted != b.artifactCompleted) {
        return a.artifactCompleted ? -1 : 1;
      }
      return a.character.name.compareTo(b.character.name);
    });
  }
  return result;
}

List<ArtifactSetOverview> buildArtifactSetOverviews({
  required List<ArtifactSetDetail> sets,
  required Map<String, List<ArtifactEquippedCharacter>> equippedBySetId,
  required Map<String, MasterCharacter> charactersById,
  required Map<String, MasterCharacter> charactersByName,
  ArtifactSetRecommendationIndex akashaByEnglishSet = const {},
  Map<String, List<String>> configRecommendationsBySetName = const {},
  Map<String, String> setNameAliases = const {},
  int maxRecommended = 8,
}) {
  final overviews = <ArtifactSetOverview>[];
  for (final set in sets) {
    final recommended = <ArtifactSetRecommendedCharacter>[];
    final seen = <String>{};

    // 1) Akasha（英語 route キー）
    final routeKey = set.route.isNotEmpty ? set.route : set.name;
    final akashaHits =
        akashaByEnglishSet[routeKey] ??
        akashaByEnglishSet.entries
            .where(
              (e) =>
                  normalizeArtifactSetKey(e.key) ==
                  normalizeArtifactSetKey(routeKey),
            )
            .map((e) => e.value)
            .firstOrNull;
    if (akashaHits != null) {
      for (final hit in akashaHits) {
        if (recommended.length >= maxRecommended) break;
        final c = charactersById[hit.characterId];
        if (c == null || !seen.add(c.id)) continue;
        recommended.add(
          ArtifactSetRecommendedCharacter(
            character: c,
            usageRate: hit.usageRate,
            source: hit.source,
          ),
        );
      }
    }

    // 2) 設定 JSON（日本語名 + エイリアス）
    if (recommended.length < maxRecommended) {
      final configNames = <String>[
        ...?configRecommendationsBySetName[set.name],
        for (final e in setNameAliases.entries)
          if (e.value == set.name ||
              normalizeArtifactSetKey(e.value) ==
                  normalizeArtifactSetKey(set.name))
            ...?configRecommendationsBySetName[e.key],
      ];
      for (final name in configNames) {
        if (recommended.length >= maxRecommended) break;
        final c = charactersByName[name] ?? charactersById[name];
        if (c == null || !seen.add(c.id)) continue;
        recommended.add(
          ArtifactSetRecommendedCharacter(character: c, source: 'config'),
        );
      }
    }

    overviews.add(
      ArtifactSetOverview(
        set: set,
        equippedCharacters: equippedBySetId[set.id] ?? const [],
        recommendedCharacters: recommended,
      ),
    );
  }
  return overviews;
}

/// 地域ごとのセクション（空地域は省略）。
class ArtifactSetRegionSection {
  const ArtifactSetRegionSection({required this.region, required this.items});

  final String region;
  final List<ArtifactSetOverview> items;
}

List<ArtifactSetRegionSection> groupArtifactSetOverviewsByRegion(
  List<ArtifactSetOverview> overviews, {
  List<String> regionOrder = const [
    'モンド',
    '璃月',
    '稲妻',
    'スメール',
    'フォンテーヌ',
    'ナタ',
    'ノド・クライ',
    'その他',
  ],
}) {
  final byRegion = <String, List<ArtifactSetOverview>>{};
  for (final o in overviews) {
    byRegion.putIfAbsent(o.set.region, () => []).add(o);
  }
  for (final list in byRegion.values) {
    list.sort((a, b) => a.set.sortOrder.compareTo(b.set.sortOrder));
  }

  final sections = <ArtifactSetRegionSection>[];
  final seen = <String>{};
  for (final region in regionOrder) {
    final items = byRegion[region];
    if (items == null || items.isEmpty) continue;
    sections.add(ArtifactSetRegionSection(region: region, items: items));
    seen.add(region);
  }
  for (final entry in byRegion.entries) {
    if (seen.contains(entry.key) || entry.value.isEmpty) continue;
    sections.add(
      ArtifactSetRegionSection(region: entry.key, items: entry.value),
    );
  }
  return sections;
}
