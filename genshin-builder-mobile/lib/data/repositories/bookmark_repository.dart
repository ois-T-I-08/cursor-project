import '../../domain/models/bookmark.dart';
import '../db/app_database.dart';

/// ブックマーク永続化 + 合算（Web `bookmark-storage.ts` / `bookmark-utils.ts` 相当）
class BookmarkRepository {
  BookmarkRepository(this._db);

  final AppDatabase _db;

  Future<List<MaterialBookmarkEntry>> getAll() => _db.getAllBookmarks();

  Future<void> addOrUpdate(MaterialBookmarkEntry entry) =>
      _db.upsertBookmark(entry);

  Future<void> remove(String id) => _db.removeBookmark(id);

  Future<void> removeBySourceKey(String sourceKey) =>
      _db.removeBookmarksBySourceKey(sourceKey);

  Future<void> removeByMaterialId(String materialId) =>
      _db.removeBookmarksByMaterialId(materialId);

  Future<void> clearAll() => _db.clearAllBookmarks();

  Future<void> replaceSourceBookmarks({
    required String sourceKey,
    required List<MaterialBookmarkEntry> entries,
  }) async {
    await _db.removeBookmarksBySourceKey(sourceKey);
    for (final e in entries) {
      await _db.upsertBookmark(e);
    }
  }

  /// materialId ごとに合算（モラは `__mora__`）
  Future<List<AggregatedMaterialBookmark>> getAggregated() async {
    final all = await getAll();
    final map = <String, AggregatedMaterialBookmark>{};

    for (final entry in all) {
      final existing = map[entry.materialId];
      if (existing == null) {
        map[entry.materialId] = AggregatedMaterialBookmark(
          materialId: entry.materialId,
          name: entry.name,
          count: entry.count,
          iconUrl: entry.iconUrl,
          isMora: entry.isMora,
          sourceLabels: [entry.sourceLabel],
          characters: _characterFromEntry(entry),
        );
      } else {
        final labels = {...existing.sourceLabels, entry.sourceLabel}.toList();
        final chars = [...existing.characters];
        for (final c in _characterFromEntry(entry)) {
          if (!chars.any((x) => x.characterId == c.characterId)) {
            chars.add(c);
          }
        }
        map[entry.materialId] = AggregatedMaterialBookmark(
          materialId: existing.materialId,
          name: existing.name,
          count: existing.count + entry.count,
          iconUrl: existing.iconUrl ?? entry.iconUrl,
          isMora: existing.isMora,
          sourceLabels: labels,
          characters: chars,
        );
      }
    }

    final merged = map.values.toList()
      ..sort((a, b) {
        if (a.isMora) return 1;
        if (b.isMora) return -1;
        return a.name.compareTo(b.name);
      });
    return merged;
  }

  List<BookmarkCharacterSource> _characterFromEntry(MaterialBookmarkEntry e) {
    if (e.characterId == null || e.characterName == null) return [];
    return [
      BookmarkCharacterSource(
        characterId: e.characterId!,
        characterName: e.characterName!,
        characterIconUrl: e.characterIconUrl,
        characterEmoji: e.characterEmoji,
      ),
    ];
  }
}
