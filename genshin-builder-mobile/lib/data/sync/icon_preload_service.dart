import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../db/app_database.dart';
import '../models/sync_status.dart';

/// マスタ同期後に CDN アイコンをディスクキャッシュへ事前取得
class IconPreloadService {
  IconPreloadService(this._db);

  final AppDatabase _db;
  static const _concurrency = 10;

  Future<int> preloadMasterIcons({
    void Function(SyncProgress progress)? onProgress,
    bool onlyMissing = false,
  }) async {
    var urls = await _collectIconUrls();
    if (onlyMissing) {
      urls = await _filterUncached(urls);
    }
    if (urls.isEmpty) {
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.iconPreload,
          current: 0,
          total: 0,
          detail: onlyMissing ? '取得済み' : null,
        ),
      );
      return 0;
    }

    var completed = 0;
    onProgress?.call(
      SyncProgress(
        phase: SyncPhase.iconPreload,
        current: 0,
        total: urls.length,
      ),
    );

    for (var i = 0; i < urls.length; i += _concurrency) {
      final batch = urls.skip(i).take(_concurrency).toList();
      await Future.wait(
        batch.map((url) async {
          try {
            await DefaultCacheManager().downloadFile(url);
          } catch (_) {
            // 個別失敗は無視（表示時に再取得）
          }
        }),
      );
      completed = (i + batch.length).clamp(0, urls.length);
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.iconPreload,
          current: completed,
          total: urls.length,
        ),
      );
    }

    return completed;
  }

  Future<List<String>> _filterUncached(List<String> urls) async {
    final cache = DefaultCacheManager();
    final missing = <String>[];

    for (var i = 0; i < urls.length; i += _concurrency) {
      final batch = urls.skip(i).take(_concurrency).toList();
      final cached = await Future.wait(
        batch.map((url) async => (url, await cache.getFileFromCache(url))),
      );
      for (final entry in cached) {
        if (entry.$2 == null) missing.add(entry.$1);
      }
    }

    return missing;
  }

  Future<List<String>> _collectIconUrls() async {
    final urls = <String>{};

    final characters = await _db.getAllCharacters();
    for (final c in characters) {
      if (c.iconUrl.isNotEmpty) urls.add(c.iconUrl);
    }

    final weapons = await _db.getAllWeapons();
    for (final w in weapons) {
      if (w.iconUrl.isNotEmpty) urls.add(w.iconUrl);
    }

    final materials = await _db.getMaterialsMap();
    for (final m in materials.values) {
      if (m.iconUrl.isNotEmpty) urls.add(m.iconUrl);
    }

    return urls.toList();
  }
}
