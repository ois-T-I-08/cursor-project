import '../hoyolab/hoyolab_constants.dart';
import '../hoyolab/hoyolab_exceptions.dart';
import '../hoyolab/hoyolab_game_data_cache.dart';
import '../hoyolab/models/game_record.dart';
import '../hoyolab/owned_characters_result.dart';
import '../repositories/hoyolab_repository.dart';

class HoyolabGameDataRepository {
  HoyolabGameDataRepository({
    required HoyolabRepository sessionRepository,
    HoyolabGameDataCache? cache,
  }) : _session = sessionRepository,
       _cache = cache ?? HoyolabGameDataCache();

  final HoyolabRepository _session;
  final HoyolabGameDataCache _cache;

  Future<OwnedCharactersFetchResult> fetchOwnedCharacters({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cache.getOwned<HoyolabOwnedCharacter>(
        HoyolabConstants.ownedCharactersCacheTtl,
      );
      if (cached != null) {
        return OwnedCharactersFetchResult(
          characters: indexOwnedCharacters(cached),
          fetched: true,
        );
      }
    }

    final api = await _session.tryApi();
    if (api == null) {
      return const OwnedCharactersFetchResult(characters: {}, notLinked: true);
    }

    try {
      final owned = await api.getOwnedCharacters();
      _cache.setOwned(owned);
      return OwnedCharactersFetchResult(
        characters: indexOwnedCharacters(owned),
        fetched: true,
      );
    } on HoyolabApiException catch (e) {
      return OwnedCharactersFetchResult(
        characters: {},
        error: e,
        fetched: true,
      );
    }
  }

  Future<Map<String, HoyolabOwnedCharacter>> fetchOwnedCharacterMap({
    bool forceRefresh = false,
  }) async {
    final result = await fetchOwnedCharacters(forceRefresh: forceRefresh);
    return result.characters;
  }

  Future<HoyolabCharacterBuild?> fetchCharacterBuild(
    String characterId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cache.getCharacterBuild<HoyolabCharacterBuild>(
        characterId,
        HoyolabConstants.characterDetailCacheTtl,
      );
      if (cached != null) return cached;
    }

    final ownedResult = await fetchOwnedCharacters();
    final summary = lookupOwnedCharacter(ownedResult.characters, characterId);
    if (summary == null) {
      return HoyolabCharacterBuild.unowned(characterId);
    }

    final api = await _session.tryApi();
    if (api == null) {
      return _buildFromSummary(summary);
    }

    try {
      final detail = await api.getCharacterBuild(characterId);
      final build =
          detail == null
              ? _buildFromSummary(summary)
              : detail.mergeSummary(summary);
      _cache.setCharacterBuild(characterId, build);
      return build;
    } on HoyolabApiException {
      final fallback = _buildFromSummary(summary);
      _cache.setCharacterBuild(characterId, fallback);
      return fallback;
    }
  }

  /// 所持キャラの装備（聖遺物）を `/character/detail` から一括取得する。
  ///
  /// `/character/list` は現代 API では聖遺物を含まない。装備集計の正本は detail。
  /// キャッシュ済みビルドは再利用し、未取得分だけバッチ取得する。
  Future<Map<String, HoyolabCharacterBuild>> fetchOwnedCharacterBuilds({
    bool forceRefresh = false,
  }) async {
    final owned = await fetchOwnedCharacterMap();
    if (owned.isEmpty) return const {};

    final result = <String, HoyolabCharacterBuild>{};
    final missing = <String>[];

    for (final id in owned.keys) {
      if (!forceRefresh) {
        final cached = _cache.getCharacterBuild<HoyolabCharacterBuild>(
          id,
          HoyolabConstants.characterDetailCacheTtl,
        );
        if (cached != null && cached.relics.isNotEmpty) {
          result[id] = cached;
          continue;
        }
      }
      missing.add(id);
    }

    if (missing.isEmpty) return result;

    final api = await _session.tryApi();
    if (api == null) {
      for (final id in missing) {
        final summary = owned[id];
        if (summary == null) continue;
        result[id] = _buildFromSummary(summary);
      }
      return result;
    }

    try {
      final builds = await api.getCharacterBuilds(missing);
      for (final build in builds) {
        final summary = lookupOwnedCharacter(owned, build.id);
        final merged = summary == null ? build : build.mergeSummary(summary);
        _cache.setCharacterBuild(merged.id, merged);
        result[merged.id] = merged;
      }
      // detail に含まれなかった所持キャラは summary フォールバック
      for (final id in missing) {
        if (result.containsKey(id)) continue;
        final summary = owned[id];
        if (summary == null) continue;
        final fallback = _buildFromSummary(summary);
        _cache.setCharacterBuild(id, fallback);
        result[id] = fallback;
      }
    } on HoyolabApiException {
      for (final id in missing) {
        if (result.containsKey(id)) continue;
        final summary = owned[id];
        if (summary == null) continue;
        final fallback = _buildFromSummary(summary);
        _cache.setCharacterBuild(id, fallback);
        result[id] = fallback;
      }
    }

    return result;
  }

  Future<AdventureStatus?> fetchAdventureStatus({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cache.getAdventure<AdventureStatus>(
        HoyolabConstants.adventureStatusCacheTtl,
      );
      if (cached != null) return cached;
    }

    final api = await _session.tryApi();
    if (api == null) return null;

    try {
      final status = await api.getAdventureStatus();
      _cache.setAdventure(status);
      return status;
    } on HoyolabApiException {
      return null;
    }
  }

  void clearCache() => _cache.clear();

  HoyolabCharacterBuild _buildFromSummary(HoyolabOwnedCharacter summary) {
    final talents = <GameRecordTalent>[];
    return HoyolabCharacterBuild(
      id: summary.id,
      isOwned: true,
      level: summary.level,
      promoteLevel: summary.promoteLevel,
      friendship: summary.friendship,
      constellation: summary.constellation,
      weapon: summary.weapon,
      relics: summary.relics,
      talents: talents,
      fetchedAt: DateTime.now(),
    );
  }
}
