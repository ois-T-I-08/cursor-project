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
  })  : _session = sessionRepository,
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
      return const OwnedCharactersFetchResult(
        characters: {},
        notLinked: true,
      );
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
      final build = detail == null
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

  Future<AdventureStatus?> fetchAdventureStatus({bool forceRefresh = false}) async {
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
