import 'package:drift/drift.dart';

import '../../../../domain/models/bookmark.dart';
import '../app_database.dart';
import '../tables/user_tables.dart';

part 'bookmark_dao.g.dart';

@DriftAccessor(tables: [MaterialBookmarks])
class BookmarkDao extends DatabaseAccessor<DriftAppDatabase>
    with _$BookmarkDaoMixin {
  BookmarkDao(super.db);

  Future<List<MaterialBookmarkEntry>> getAllBookmarks() async {
    final rows = await (select(materialBookmarks)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .get();
    return rows.map(_bookmarkFromRow).toList();
  }

  Future<void> upsertBookmark(MaterialBookmarkEntry entry) async {
    await (delete(materialBookmarks)
          ..where((t) =>
              t.sourceKey.equals(entry.sourceKey) &
              t.materialId.equals(entry.materialId)))
        .go();
    await into(materialBookmarks).insert(_bookmarkToCompanion(entry));
  }

  Future<void> removeBookmark(String id) async {
    await (delete(materialBookmarks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> removeBookmarksBySourceKey(String sourceKey) async {
    await (delete(materialBookmarks)
          ..where((t) => t.sourceKey.equals(sourceKey)))
        .go();
  }

  Future<void> removeBookmarksByMaterialId(String materialId) async {
    await (delete(materialBookmarks)
          ..where((t) => t.materialId.equals(materialId)))
        .go();
  }

  Future<void> clearAllBookmarks() async {
    await delete(materialBookmarks).go();
  }

  MaterialBookmarkEntry _bookmarkFromRow(MaterialBookmark row) =>
      MaterialBookmarkEntry(
        id: row.id,
        sourceKey: row.sourceKey,
        sourceLabel: row.sourceLabel,
        materialId: row.materialId,
        name: row.name,
        count: row.count,
        iconUrl: row.iconUrl,
        characterId: row.characterId,
        characterName: row.characterName,
        characterIconUrl: row.characterIconUrl,
        characterEmoji: row.characterEmoji,
        addedAt: row.addedAt,
      );

  MaterialBookmarksCompanion _bookmarkToCompanion(MaterialBookmarkEntry e) =>
      MaterialBookmarksCompanion.insert(
        id: e.id,
        sourceKey: e.sourceKey,
        sourceLabel: e.sourceLabel,
        materialId: e.materialId,
        name: e.name,
        count: e.count,
        iconUrl: Value(e.iconUrl),
        characterId: Value(e.characterId),
        characterName: Value(e.characterName),
        characterIconUrl: Value(e.characterIconUrl),
        characterEmoji: Value(e.characterEmoji),
        addedAt: e.addedAt,
      );
}
