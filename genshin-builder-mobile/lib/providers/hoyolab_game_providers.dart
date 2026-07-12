import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hoyolab/hoyolab_character_discovery_store.dart';
import '../data/hoyolab/hoyolab_game_data_cache.dart';
import '../data/hoyolab/hoyolab_game_data_repository.dart';
import '../data/hoyolab/hoyolab_home_disk_cache.dart';
import '../data/hoyolab/models/game_record.dart';
import '../data/hoyolab/owned_characters_result.dart';
import '../domain/character_list_sort.dart';
import 'app_providers.dart';
import 'hoyolab_providers.dart';

final hoyolabGameDataCacheProvider = Provider<HoyolabGameDataCache>((ref) {
  final cache = HoyolabGameDataCache();
  ref.onDispose(cache.clear);
  return cache;
});

final hoyolabGameDataRepositoryProvider =
    FutureProvider<HoyolabGameDataRepository>((ref) async {
  final sessionRepo = await ref.watch(hoyolabRepositoryProvider.future);
  final cache = ref.watch(hoyolabGameDataCacheProvider);
  return HoyolabGameDataRepository(
    sessionRepository: sessionRepo,
    cache: cache,
  );
});

final hoyolabCharacterDiscoveryStoreProvider =
    FutureProvider<HoyolabCharacterDiscoveryStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return HoyolabCharacterDiscoveryStore(AppDatabaseSettingsStore(db));
});

final hoyolabOwnedFetchResultProvider =
    FutureProvider<OwnedCharactersFetchResult>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.hoyolabLinkEnabled) {
    return const OwnedCharactersFetchResult(characters: {});
  }
  final session = await ref.watch(hoyolabSessionProvider.future);
  if (!session.isLinked) {
    return const OwnedCharactersFetchResult(characters: {}, notLinked: true);
  }
  final repo = await ref.watch(hoyolabGameDataRepositoryProvider.future);
  final result = await repo.fetchOwnedCharacters();
  final uid = session.uid;
  if (uid == null || uid.isEmpty || !result.hasCharacters) {
    return result;
  }

  final discoveryStore =
      await ref.watch(hoyolabCharacterDiscoveryStoreProvider.future);
  final enriched = await discoveryStore.enrichOwnedCharacters(
    uid: uid,
    characters: result.characters,
  );
  return result.copyWith(characters: enriched);
});

final hoyolabOwnedCharacterMapProvider =
    FutureProvider<Map<String, HoyolabOwnedCharacter>>((ref) async {
  final result = await ref.watch(hoyolabOwnedFetchResultProvider.future);
  return result.characters;
});

final sortedCharacterEntriesProvider =
    FutureProvider<List<CharacterListEntry>>((ref) async {
  final characters = await ref.watch(charactersProvider.future);
  final ownedMap = await ref.watch(hoyolabOwnedCharacterMapProvider.future);
  // 聖遺物一覧と同じ地域順（保存済みソート設定は使わない）
  const sortSettings = CharacterListSortSettings(
    mode: CharacterListSortMode.region,
    groupByOwnership: false,
  );
  final sortOwned = <String, OwnedCharacterSortInfo>{
    for (final e in ownedMap.entries)
      e.key: OwnedCharacterSortInfo(
        level: e.value.level,
        friendship: e.value.friendship,
        constellation: e.value.constellation,
        obtainedAt: e.value.obtainedAt,
      ),
  };
  return buildCharacterListEntries(
    characters: characters,
    ownedMap: sortOwned,
    settings: sortSettings,
  );
});

final hoyolabCharacterBuildProvider = FutureProvider.family<
    HoyolabCharacterBuild?,
    String>((ref, characterId) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.hoyolabLinkEnabled) return null;
  final session = await ref.watch(hoyolabSessionProvider.future);
  if (!session.isLinked) return null;
  final repo = await ref.watch(hoyolabGameDataRepositoryProvider.future);
  return repo.fetchCharacterBuild(characterId);
});
