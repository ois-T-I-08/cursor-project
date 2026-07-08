class CacheEntry<T> {
  CacheEntry(this.data, this.fetchedAt);

  final T data;
  final DateTime fetchedAt;

  bool isValid(Duration ttl) => DateTime.now().difference(fetchedAt) < ttl;
}

/// シンプルなインメモリ TTL キャッシュ
class HoyolabGameDataCache {
  CacheEntry<List<dynamic>>? _owned;
  final _characterBuilds = <String, CacheEntry<dynamic>>{};
  CacheEntry<dynamic>? _adventure;

  List<T>? readList<T>({
    required CacheEntry<List<dynamic>>? entry,
    required Duration ttl,
  }) {
    if (entry == null || !entry.isValid(ttl)) return null;
    return entry.data.cast<T>();
  }

  T? readSingle<T>({
    required CacheEntry<dynamic>? entry,
    required Duration ttl,
  }) {
    if (entry == null || !entry.isValid(ttl)) return null;
    return entry.data as T;
  }

  List<T>? getOwned<T>(Duration ttl) =>
      readList<T>(entry: _owned, ttl: ttl);

  void setOwned<T>(List<T> data) =>
      _owned = CacheEntry<List<dynamic>>(data, DateTime.now());

  T? getCharacterBuild<T>(String id, Duration ttl) =>
      readSingle<T>(entry: _characterBuilds[id], ttl: ttl);

  void setCharacterBuild<T>(String id, T data) =>
      _characterBuilds[id] = CacheEntry<dynamic>(data, DateTime.now());

  T? getAdventure<T>(Duration ttl) => readSingle<T>(entry: _adventure, ttl: ttl);

  void setAdventure<T>(T data) =>
      _adventure = CacheEntry<dynamic>(data, DateTime.now());

  void clear() {
    _owned = null;
    _characterBuilds.clear();
    _adventure = null;
  }
}
