import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/bookmark_utils.dart';
import '../../../domain/models/bookmark.dart';
import '../../../providers/app_providers.dart';

/// キャラ詳細画面のブックマーク操作（UI 状態への依存をコールバックで受け取る）
class CharacterDetailBookmarkActions {
  CharacterDetailBookmarkActions({
    required this.ref,
    required this.getContext,
    required this.getBookmarks,
    required this.setBookmarks,
    required this.onStateChanged,
    required this.getMaterials,
    required this.getLevel,
    required this.getTargetLevel,
    required this.getWeaponLevel,
    required this.getTargetWeaponLevel,
  });

  final WidgetRef ref;
  final BuildContext Function() getContext;
  final List<MaterialBookmarkEntry> Function() getBookmarks;
  final void Function(List<MaterialBookmarkEntry>) setBookmarks;
  final VoidCallback onStateChanged;
  final Map<String, MasterMaterial> Function() getMaterials;
  final int Function() getLevel;
  final int Function() getTargetLevel;
  final int Function() getWeaponLevel;
  final int Function() getTargetWeaponLevel;

  bool isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(getBookmarks(), sourceKey, materialId);

  Map<String, String?> _iconMap() => {
    for (final m in getMaterials().values) m.id: m.iconUrl,
  };

  int _rangeFrom(CultivationBookmarkContext ctx) =>
      ctx.kind == CultivationKind.weaponLevel ? getWeaponLevel() : getLevel();

  int _rangeTo(CultivationBookmarkContext ctx) =>
      ctx.kind == CultivationKind.weaponLevel
          ? getTargetWeaponLevel()
          : getTargetLevel();

  Future<void> bookmarkRange(
    CultivationBookmarkContext ctx,
    List<RequirementLine> lines,
    String sourceKey,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final sourceLabel = makeRangeSourceLabel(
      ctx,
      _rangeFrom(ctx),
      _rangeTo(ctx),
    );
    final entries = buildBookmarkEntries(
      lines: lines,
      sourceKey: sourceKey,
      sourceLabel: sourceLabel,
      character: ctx.character,
      iconUrlByMaterialId: _iconMap(),
    );
    await repo.replaceSourceBookmarks(sourceKey: sourceKey, entries: entries);
    setBookmarks(await repo.getAll());
    ref.invalidate(aggregatedBookmarksProvider);
    final context = getContext();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ブックマークに追加しました')));
    }
    onStateChanged();
  }

  Future<void> toggleRangeLineBookmark(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String rangeSourceKey,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final id = makeBookmarkId(rangeSourceKey, line.materialId);
    final bookmarks = getBookmarks();
    if (isBookmarked(rangeSourceKey, line.materialId)) {
      await repo.remove(id);
      bookmarks.removeWhere((b) => b.id == id);
      setBookmarks(bookmarks);
    } else {
      final entry =
          buildBookmarkEntries(
            lines: [line],
            sourceKey: rangeSourceKey,
            sourceLabel: makeRangeSourceLabel(
              ctx,
              _rangeFrom(ctx),
              _rangeTo(ctx),
            ),
            character: ctx.character,
            iconUrlByMaterialId: _iconMap(),
          ).first;
      await repo.addOrUpdate(entry);
      setBookmarks([...bookmarks, entry]);
    }
    ref.invalidate(aggregatedBookmarksProvider);
    onStateChanged();
  }

  Future<void> toggleLineBookmark(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String scope,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final sourceKey = makeItemSourceKey(ctx, scope, line.materialId);
    final id = makeBookmarkId(sourceKey, line.materialId);
    final bookmarks = getBookmarks();
    if (isBookmarked(sourceKey, line.materialId)) {
      await repo.remove(id);
      bookmarks.removeWhere((b) => b.id == id);
      setBookmarks(bookmarks);
    } else {
      final entry =
          buildBookmarkEntries(
            lines: [line],
            sourceKey: sourceKey,
            sourceLabel: makeItemSourceLabel(ctx, line.name),
            character: ctx.character,
            iconUrlByMaterialId: _iconMap(),
          ).first;
      await repo.addOrUpdate(entry);
      setBookmarks([...bookmarks, entry]);
    }
    ref.invalidate(aggregatedBookmarksProvider);
    onStateChanged();
  }
}
