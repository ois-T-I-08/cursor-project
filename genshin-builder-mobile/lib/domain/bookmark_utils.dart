import 'models/bookmark.dart';

/// Web `bookmark-utils.ts` 相当 — sourceKey / エントリ生成

String cultivationKindKey(CultivationKind kind) => switch (kind) {
  CultivationKind.characterLevel => 'character-level',
  CultivationKind.weaponLevel => 'weapon-level',
  CultivationKind.talent => 'talent',
};

String makeRangeSourceKey(CultivationBookmarkContext ctx, int from, int to) {
  final sub = ctx.subLabel != null ? ':${ctx.subLabel}' : '';
  return 'range:${cultivationKindKey(ctx.kind)}:${ctx.targetId}$sub:$from-$to';
}

String makeItemSourceKey(
  CultivationBookmarkContext ctx,
  String scope,
  String materialId,
) {
  final sub = ctx.subLabel != null ? ':${ctx.subLabel}' : '';
  return 'item:${cultivationKindKey(ctx.kind)}:${ctx.targetId}$sub:$scope:$materialId';
}

String makeRangeSourceLabel(CultivationBookmarkContext ctx, int from, int to) {
  final prefix = switch (ctx.kind) {
    CultivationKind.characterLevel => 'キャラLv',
    CultivationKind.weaponLevel => '武器Lv',
    CultivationKind.talent => '天賦',
  };
  final sub = ctx.subLabel != null ? ' ${ctx.subLabel}' : '';
  return '${ctx.targetName} $prefix$sub $from→$to';
}

String makeItemSourceLabel(
  CultivationBookmarkContext ctx,
  String materialName,
) {
  final prefix = switch (ctx.kind) {
    CultivationKind.characterLevel => 'キャラ',
    CultivationKind.weaponLevel => '武器',
    CultivationKind.talent => '天賦',
  };
  final sub = ctx.subLabel != null ? ' ${ctx.subLabel}' : '';
  return '${ctx.targetName} $prefix$sub · $materialName';
}

String makeBookmarkId(String sourceKey, String materialId) =>
    '$sourceKey:$materialId';

bool isMaterialBookmarked(
  List<MaterialBookmarkEntry> entries,
  String sourceKey,
  String materialId,
) => entries.any((e) => e.sourceKey == sourceKey && e.materialId == materialId);

List<MaterialBookmarkEntry> buildBookmarkEntries({
  required List<RequirementLine> lines,
  required String sourceKey,
  required String sourceLabel,
  required BookmarkCharacterSource character,
  Map<String, String?>? iconUrlByMaterialId,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return lines
      .map(
        (line) => MaterialBookmarkEntry(
          id: makeBookmarkId(sourceKey, line.materialId),
          sourceKey: sourceKey,
          sourceLabel: sourceLabel,
          materialId: line.materialId,
          name: line.name,
          count: line.count,
          iconUrl:
              line.iconUrl ??
              (line.isMora ? null : iconUrlByMaterialId?[line.materialId]),
          characterId: character.characterId,
          characterName: character.characterName,
          characterIconUrl: character.characterIconUrl,
          characterEmoji: character.characterEmoji,
          addedAt: now,
        ),
      )
      .toList();
}

String formatMora(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);
