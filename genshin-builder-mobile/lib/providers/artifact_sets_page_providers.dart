import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/hoyolab/sync_hoyolab_relics_to_progress_use_case.dart';
import '../data/akasha/akasha_artifact_set_usage_repository.dart';
import '../data/config/artifact_set_recommendations_loader.dart';
import '../data/hoyolab/models/game_record.dart';
import '../domain/artifacts/artifact_set_overview.dart';
import '../domain/artifacts/character_recommended_artifact_sets.dart';
import '../domain/models/artifact_state.dart';
import '../domain/models/master_models.dart';
import 'app_providers.dart';
import 'character_detail_providers.dart';
import 'hoyolab_game_providers.dart';

final artifactSetRecommendationsConfigProvider =
    FutureProvider<ArtifactSetRecommendationsConfig>((ref) {
  return const ArtifactSetRecommendationsLoader().load();
});

final akashaArtifactSetUsageRepositoryProvider =
    Provider<AkashaArtifactSetUsageRepository>((ref) {
  final repo = AkashaArtifactSetUsageRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// セット一覧の Akasha 取得キャラ数上限（所持優先で切り詰め）。
const int kArtifactAkashaSampleLimit = 32;

/// Akasha 集計用のキャラ ID。
///
/// 優先: 所持 → 聖遺物進捗（setName あり）。未所持・未進捗の全マスタは含めない。
/// [allCharacters] は呼び出し互換のため残す（P1-5 以降はサンプリングに使わない）。
List<String> selectArtifactRecommendationSampleIds({
  required Set<String> ownedIds,
  required List<UserProgress> progressList,
  required List<MasterCharacter> allCharacters,
  int maxSampleIds = kArtifactAkashaSampleLimit,
}) {
  // 呼び出し互換（未使用）。全マスタ埋め込みは負荷のため廃止。
  assert(() {
    allCharacters.length;
    return true;
  }());

  final ordered = <String>[];
  final seen = <String>{};

  void add(String id) {
    if (id.isEmpty || !seen.add(id)) return;
    ordered.add(id);
  }

  for (final id in ownedIds) {
    add(id);
  }

  for (final p in progressList) {
    final hasSet = p.artifacts.values.any((a) => a.setName.trim().isNotEmpty);
    if (hasSet) add(p.characterId);
  }

  if (maxSampleIds <= 0) return const [];
  if (ordered.length <= maxSampleIds) return ordered;
  return ordered.sublist(0, maxSampleIds);
}

/// HoYoLAB 聖遺物 → 突合用 [ArtifactPiece]（スロット不要・件数集計用）。
ArtifactPiece artifactPieceFromHoyolabRelic(GameRecordRelic relic) {
  return ArtifactPiece(
    setName: relic.setName,
    level: relic.level,
    iconUrl: relic.iconUrl,
    name: relic.name,
  );
}

/// マスター ID 解決（旅人の `10000005-anemo` 等を HoYoLAB の `10000005` に合わせる）。
String? resolveMasterCharacterId(
  String hoyolabOrMasterId,
  Map<String, MasterCharacter> charactersById,
) {
  if (charactersById.containsKey(hoyolabOrMasterId)) {
    return hoyolabOrMasterId;
  }
  final base = hoyolabOrMasterId.split('-').first;
  if (charactersById.containsKey(base)) return base;
  for (final id in charactersById.keys) {
    if (id == base || id.startsWith('$base-')) return id;
  }
  return null;
}

/// 装備入力を組み立てる。
///
/// 優先順位:
/// 1. `/character/detail` の relics（現代 API の正本）
/// 2. 所持一覧に載っている relics（レガシー `/character` 等）
/// 3. ローカル進捗 JSON（オフライン・未同期のフォールバック）
List<ArtifactEquipInput> buildArtifactEquipInputs({
  required Map<String, HoyolabOwnedCharacter> ownedMap,
  required List<UserProgress> progressList,
  Map<String, HoyolabCharacterBuild> detailBuilds = const {},
  Map<String, MasterCharacter> charactersById = const {},
}) {
  final progressById = {for (final p in progressList) p.characterId: p};
  final inputs = <ArtifactEquipInput>[];
  final seenMasterIds = <String>{};

  void addInput({
    required String sourceCharacterId,
    required Iterable<ArtifactPiece> pieces,
    required bool artifactCompleted,
  }) {
    final masterId = charactersById.isEmpty
        ? sourceCharacterId
        : (resolveMasterCharacterId(sourceCharacterId, charactersById) ??
            sourceCharacterId);
    if (!seenMasterIds.add(masterId)) return;
    inputs.add(
      ArtifactEquipInput(
        characterId: masterId,
        pieces: pieces,
        artifactCompleted: artifactCompleted,
      ),
    );
  }

  // 1) detail builds
  for (final entry in detailBuilds.entries) {
    final relics = entry.value.relics;
    if (relics.isEmpty) continue;
    final progress = progressById[entry.key] ??
        progressById[resolveMasterCharacterId(entry.key, charactersById) ?? ''];
    addInput(
      sourceCharacterId: entry.key,
      pieces: relics.map(artifactPieceFromHoyolabRelic),
      artifactCompleted: progress?.artifactCompleted ?? false,
    );
  }

  // 2) owned list relics（detail に無い／空のとき）
  for (final entry in ownedMap.entries) {
    final relics = entry.value.relics;
    if (relics.isEmpty) continue;
    final masterId = charactersById.isEmpty
        ? entry.key
        : (resolveMasterCharacterId(entry.key, charactersById) ?? entry.key);
    if (seenMasterIds.contains(masterId)) continue;
    addInput(
      sourceCharacterId: entry.key,
      pieces: relics.map(artifactPieceFromHoyolabRelic),
      artifactCompleted: progressById[masterId]?.artifactCompleted ??
          progressById[entry.key]?.artifactCompleted ??
          false,
    );
  }

  // 3) progress fallback
  for (final progress in progressList) {
    final masterId = charactersById.isEmpty
        ? progress.characterId
        : (resolveMasterCharacterId(progress.characterId, charactersById) ??
            progress.characterId);
    if (seenMasterIds.contains(masterId)) continue;
    final pieces = progress.artifacts.values.where(
      (p) =>
          p.setName.trim().isNotEmpty ||
          (p.iconUrl != null && p.iconUrl!.trim().isNotEmpty),
    );
    if (pieces.isEmpty) continue;
    addInput(
      sourceCharacterId: progress.characterId,
      pieces: pieces,
      artifactCompleted: progress.artifactCompleted,
    );
  }

  return inputs;
}

/// 聖遺物セット一覧（効果・装備キャラ・推奨）。
final artifactSetOverviewsProvider =
    FutureProvider<List<ArtifactSetOverview>>((ref) async {
  final sets = await ref.watch(artifactSetsProvider.future);
  final characters = await ref.watch(charactersProvider.future);
  final progressRepo = await ref.watch(progressRepositoryProvider.future);
  final userId = await ref.watch(localUserIdProvider.future);
  final progressList = await progressRepo.getAll(userId);
  final config =
      await ref.watch(artifactSetRecommendationsConfigProvider.future);
  final ownedMap = await ref.watch(hoyolabOwnedCharacterMapProvider.future);
  final ownedIds = ownedMap.keys.toSet();

  // 装備の正本: /character/detail（list には聖遺物が無い）
  var detailBuilds = <String, HoyolabCharacterBuild>{};
  if (ownedMap.isNotEmpty) {
    try {
      final repo = await ref.watch(hoyolabGameDataRepositoryProvider.future);
      detailBuilds = await repo.fetchOwnedCharacterBuilds();
      // Persist so account health / snapshot see the same relic data.
      await SyncHoyolabRelicsToProgressUseCase(
        progressRepository: progressRepo,
      )(userId: userId, builds: detailBuilds.values);
    } catch (_) {
      // 詳細取得失敗時は owned/progress フォールバック
    }
  }

  final byId = {for (final c in characters) c.id: c};
  final byName = <String, MasterCharacter>{
    for (final c in characters) c.name: c,
  };
  final catalog = ArtifactSetCatalog.fromSets(
    sets,
    aliases: config.aliases,
  );

  final equipped = groupEquippedBySetId(
    inputs: buildArtifactEquipInputs(
      ownedMap: ownedMap,
      progressList: progressList,
      detailBuilds: detailBuilds,
      charactersById: byId,
    ),
    charactersById: byId,
    ownedCharacterIds: {
      for (final id in ownedIds)
        resolveMasterCharacterId(id, byId) ?? id,
    },
    catalog: catalog,
  );

  final sampleIds = selectArtifactRecommendationSampleIds(
    ownedIds: ownedIds,
    progressList: progressList,
    allCharacters: characters,
  );

  var akashaIndex = <String, List<ArtifactSetRecommendationHit>>{};
  if (sampleIds.isNotEmpty) {
    final usageRepo = ref.watch(akashaArtifactSetUsageRepositoryProvider);
    final snaps = await usageRepo.getUsageRatesForCharacters(
      sampleIds,
      concurrency: 4,
    );
    akashaIndex = invertCharacterSetUsage(
      snapshots: snaps.map(
        (s) => (
          characterId: s.characterId,
          rates: s.rates,
          isRemote: s.isFromRemote,
        ),
      ),
    );
  }

  return buildArtifactSetOverviews(
    sets: sets,
    equippedBySetId: equipped,
    charactersById: byId,
    charactersByName: byName,
    akashaByEnglishSet: akashaIndex,
    configRecommendationsBySetName: config.recommendations,
    setNameAliases: config.aliases,
  );
});

/// キャラ別おすすめ聖遺物セット（Akasha 使用率 → 設定フォールバック）
final characterRecommendedArtifactSetsProvider = FutureProvider.family<
    List<CharacterRecommendedArtifactSet>, String>((ref, characterId) async {
  final characters = await ref.watch(charactersProvider.future);
  MasterCharacter? character;
  for (final c in characters) {
    if (c.id == characterId) {
      character = c;
      break;
    }
  }
  if (character == null) return const [];

  final sets = await ref.watch(artifactSetsProvider.future);
  final config =
      await ref.watch(artifactSetRecommendationsConfigProvider.future);
  final snap = await ref
      .watch(akashaArtifactSetUsageRepositoryProvider)
      .getUsageRates(characterId);

  return buildCharacterRecommendedArtifactSets(
    characterId: character.id,
    characterName: character.name,
    sets: sets,
    akashaRates: snap.isFromRemote ? snap.rates : const {},
    configRecommendationsBySetName: config.recommendations,
    setNameAliases: config.aliases,
  );
});
