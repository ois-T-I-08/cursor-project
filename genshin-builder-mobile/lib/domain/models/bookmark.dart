/// ブックマーク型（Web `types/bookmark.ts` 相当）
library;

const moraMaterialId = '__mora__';

enum CultivationKind {
  characterLevel,
  weaponLevel,
  talent,
}

class BookmarkCharacterSource {
  const BookmarkCharacterSource({
    required this.characterId,
    required this.characterName,
    this.characterIconUrl,
    this.characterEmoji,
  });

  final String characterId;
  final String characterName;
  final String? characterIconUrl;
  final String? characterEmoji;
}

class MaterialBookmarkEntry {
  const MaterialBookmarkEntry({
    required this.id,
    required this.sourceKey,
    required this.sourceLabel,
    required this.materialId,
    required this.name,
    required this.count,
    this.iconUrl,
    this.characterId,
    this.characterName,
    this.characterIconUrl,
    this.characterEmoji,
    required this.addedAt,
  });

  final String id;
  final String sourceKey;
  final String sourceLabel;
  final String materialId;
  final String name;
  final int count;
  final String? iconUrl;
  final String? characterId;
  final String? characterName;
  final String? characterIconUrl;
  final String? characterEmoji;
  final int addedAt;

  bool get isMora => materialId == moraMaterialId;

  MaterialBookmarkEntry copyWith({int? count}) {
    return MaterialBookmarkEntry(
      id: id,
      sourceKey: sourceKey,
      sourceLabel: sourceLabel,
      materialId: materialId,
      name: name,
      count: count ?? this.count,
      iconUrl: iconUrl,
      characterId: characterId,
      characterName: characterName,
      characterIconUrl: characterIconUrl,
      characterEmoji: characterEmoji,
      addedAt: addedAt,
    );
  }
}

class AggregatedMaterialBookmark {
  const AggregatedMaterialBookmark({
    required this.materialId,
    required this.name,
    required this.count,
    this.iconUrl,
    required this.isMora,
    required this.sourceLabels,
    required this.characters,
  });

  final String materialId;
  final String name;
  final int count;
  final String? iconUrl;
  final bool isMora;
  final List<String> sourceLabels;
  final List<BookmarkCharacterSource> characters;
}

class RequirementLine {
  const RequirementLine({
    required this.materialId,
    required this.name,
    required this.count,
    this.iconUrl,
    this.isMora = false,
  });

  final String materialId;
  final String name;
  final int count;
  final String? iconUrl;
  final bool isMora;
}

class CultivationBookmarkContext {
  const CultivationBookmarkContext({
    required this.kind,
    required this.targetId,
    required this.targetName,
    this.subLabel,
    required this.character,
  });

  final CultivationKind kind;
  final String targetId;
  final String targetName;
  final String? subLabel;
  final BookmarkCharacterSource character;
}
