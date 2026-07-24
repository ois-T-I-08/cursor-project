import '../../domain/battle_statistics/battle_statistics.dart';
import '../../domain/repositories/battle_statistics_repository.dart';
import '../../domain/repositories/character_repository.dart';

class BattleStatisticsSyncResult {
  const BattleStatisticsSyncResult({
    required this.states,
    required this.manifestNotModified,
  });

  final Map<BattleStatsContentType, RemoteBattleStatsState> states;
  final bool manifestNotModified;
}

class SyncBattleStatisticsUseCase {
  SyncBattleStatisticsUseCase({
    required this.remote,
    required this.repository,
    required this.characterRepository,
    required this.integrityVerifier,
  });

  static const supportedSchemaVersion = 1;
  static const maxBundlePages = 1000;

  final BattleStatisticsRemoteSource remote;
  final BattleStatisticsRepository repository;
  final CharacterRepository characterRepository;
  final BattleStatsIntegrityVerifier integrityVerifier;

  Future<BattleStatisticsSyncResult> execute() async {
    final states = <BattleStatsContentType, RemoteBattleStatsState>{};
    final etag = await repository.readManifestEtag();
    BattleStatsManifestFetchResult response;
    try {
      response = await remote.fetchManifest(etag: etag);
    } catch (_) {
      for (final type in BattleStatsContentType.values) {
        states[type] = RemoteBattleStatsState.offlineUsingCache;
        await repository.recordSyncState(
          type,
          RemoteBattleStatsState.offlineUsingCache,
          errorCode: 'manifest_unavailable',
        );
      }
      return BattleStatisticsSyncResult(
        states: states,
        manifestNotModified: false,
      );
    }
    if (response.notModified) {
      for (final type in BattleStatsContentType.values) {
        states[type] = RemoteBattleStatsState.current;
      }
      return BattleStatisticsSyncResult(
        states: states,
        manifestNotModified: true,
      );
    }

    final manifest = response.manifest;
    if (manifest == null) {
      throw const FormatException('manifest missing');
    }
    if (manifest.schemaVersion != supportedSchemaVersion) {
      for (final type in manifest.items.keys) {
        states[type] = RemoteBattleStatsState.unsupportedSchema;
        await repository.recordSyncState(
          type,
          RemoteBattleStatsState.unsupportedSchema,
          errorCode: 'unsupported_schema',
        );
      }
      return BattleStatisticsSyncResult(
        states: states,
        manifestNotModified: false,
      );
    }

    final master = await characterRepository.getAll();
    final knownCharacterIds = master.map((character) => character.id).toSet();
    var allChangedTypesSucceeded = true;
    for (final entry in manifest.items.entries) {
      final type = entry.key;
      final remoteItem = entry.value;
      final local = await repository.readManifest(type);
      if (local?.revision == remoteItem.revision &&
          local?.payloadHash == remoteItem.payloadHash) {
        states[type] = RemoteBattleStatsState.current;
        await repository.recordSyncState(type, RemoteBattleStatsState.current);
        continue;
      }
      states[type] = RemoteBattleStatsState.updateAvailable;
      await repository.recordSyncState(type, RemoteBattleStatsState.syncing);
      try {
        final bundle = await _downloadBundle(type, remoteItem);
        _validateBundle(bundle, knownCharacterIds);
        if (!integrityVerifier.matches(bundle)) {
          throw const FormatException('payload hash mismatch');
        }
        await repository.replaceBundle(bundle);
        await repository.recordSyncState(type, RemoteBattleStatsState.valid);
        states[type] = RemoteBattleStatsState.valid;
      } catch (_) {
        allChangedTypesSucceeded = false;
        states[type] = RemoteBattleStatsState.invalid;
        await repository.recordSyncState(
          type,
          RemoteBattleStatsState.invalid,
          errorCode: 'bundle_invalid',
        );
      }
    }
    if (allChangedTypesSucceeded && manifest.etag != null) {
      await repository.writeManifestEtag(manifest.etag!);
    }
    return BattleStatisticsSyncResult(
      states: states,
      manifestNotModified: false,
    );
  }

  Future<BattleStatsBundle> _downloadBundle(
    BattleStatsContentType type,
    BattleStatsManifestItem manifest,
  ) async {
    final teams = <RemoteBattleTeam>[];
    final characters = <RemoteBattleCharacterUsage>[];
    BattleStatsBundlePage? first;
    var page = 0;
    while (true) {
      if (page >= maxBundlePages) {
        throw const FormatException('too many bundle pages');
      }
      final current = await remote.fetchBundlePage(
        contentType: type,
        revision: manifest.revision,
        page: page,
      );
      first ??= current;
      if (!_sameBundle(first, current) ||
          current.page != page ||
          current.pageCount > maxBundlePages) {
        throw const FormatException('inconsistent bundle page');
      }
      teams.addAll(current.teams);
      characters.addAll(current.characters);
      page++;
      if (page >= current.pageCount) break;
    }
    final metadata = first;
    return BattleStatsBundle(
      schemaVersion: metadata.schemaVersion,
      contentType: metadata.contentType,
      sourceVersion: metadata.sourceVersion,
      seasonId: metadata.seasonId,
      revision: metadata.revision,
      payloadHash: metadata.payloadHash,
      sourceUpdatedAt: metadata.sourceUpdatedAt,
      sampleSize: metadata.sampleSize,
      teams: teams,
      characters: characters,
    );
  }

  bool _sameBundle(BattleStatsBundlePage first, BattleStatsBundlePage current) {
    return first.schemaVersion == current.schemaVersion &&
        first.contentType == current.contentType &&
        first.sourceVersion == current.sourceVersion &&
        first.seasonId == current.seasonId &&
        first.revision == current.revision &&
        first.payloadHash == current.payloadHash &&
        first.sourceUpdatedAt == current.sourceUpdatedAt &&
        first.sampleSize == current.sampleSize &&
        first.pageCount == current.pageCount;
  }

  void _validateBundle(
    BattleStatsBundle bundle,
    Set<String> knownCharacterIds,
  ) {
    if (bundle.schemaVersion != supportedSchemaVersion ||
        bundle.teams.isEmpty && bundle.characters.isEmpty) {
      throw const FormatException('unsupported or empty bundle');
    }
    final teamKeys = <String>{};
    for (final team in bundle.teams) {
      final scope = '${team.teamKey}|${team.side ?? ''}|${team.stageKey ?? ''}';
      if (!teamKeys.add(scope) ||
          team.members.length != 4 ||
          team.members.toSet().length != 4 ||
          team.members.any((id) => !knownCharacterIds.contains(id)) ||
          !team.usageRate.isFinite ||
          team.usageRate < 0 ||
          team.usageRate > 1) {
        throw const FormatException('invalid team');
      }
    }
    final characterKeys = <String>{};
    for (final character in bundle.characters) {
      final scope = '${character.characterId}|${character.side ?? ''}';
      if (!characterKeys.add(scope) ||
          !knownCharacterIds.contains(character.characterId) ||
          !character.usageRate.isFinite ||
          character.usageRate < 0 ||
          character.usageRate > 1) {
        throw const FormatException('invalid character');
      }
    }
  }
}
