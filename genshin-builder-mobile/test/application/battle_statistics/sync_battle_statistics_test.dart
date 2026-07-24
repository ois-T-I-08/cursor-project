import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/application/battle_statistics/sync_battle_statistics.dart';
import 'package:genshin_builder_mobile/domain/battle_statistics/battle_statistics.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/repositories/battle_statistics_repository.dart';
import 'package:genshin_builder_mobile/domain/repositories/character_repository.dart';

void main() {
  test('same revision and hash do not fetch a bundle', () async {
    final repository =
        _FakeRepository()..manifests[BattleStatsContentType.abyss] = _item;
    final remote = _FakeRemote(_manifest());
    final result = await _useCase(repository, remote).execute();

    expect(
      result.states[BattleStatsContentType.abyss],
      RemoteBattleStatsState.current,
    );
    expect(remote.bundleCalls, 0);
    expect(repository.replaced, isEmpty);
  });

  test('changed revision downloads all pages and replaces once', () async {
    final repository = _FakeRepository();
    final remote = _FakeRemote(
      _manifest(),
      pages: [_page(page: 0, pageCount: 2), _page(page: 1, pageCount: 2)],
    );
    final result = await _useCase(repository, remote).execute();

    expect(
      result.states[BattleStatsContentType.abyss],
      RemoteBattleStatsState.valid,
    );
    expect(remote.bundleCalls, 2);
    expect(repository.replaced.single.teams, hasLength(2));
    expect(repository.etag, '"fixture"');
  });

  test('hash mismatch does not replace the last successful bundle', () async {
    final repository = _FakeRepository()..storedBundle = _bundle();
    final remote = _FakeRemote(_manifest(), pages: [_page()]);
    final result =
        await _useCase(
          repository,
          remote,
          verifier: const _Verifier(false),
        ).execute();

    expect(
      result.states[BattleStatsContentType.abyss],
      RemoteBattleStatsState.invalid,
    );
    expect(repository.replaced, isEmpty);
    expect(repository.storedBundle?.revision, 1);
    expect(repository.etag, isNull);
  });

  test('offline manifest check uses the existing cache', () async {
    final repository = _FakeRepository();
    final remote = _FakeRemote(_manifest())..failManifest = true;
    final result = await _useCase(repository, remote).execute();

    expect(
      result.states.values,
      everyElement(RemoteBattleStatsState.offlineUsingCache),
    );
    expect(repository.replaced, isEmpty);
  });

  test('unsupported schema does not fetch or replace a bundle', () async {
    final repository = _FakeRepository();
    final remote = _FakeRemote(
      BattleStatsManifest(
        schemaVersion: 2,
        items: {BattleStatsContentType.abyss: _item},
        etag: '"future"',
      ),
    );
    final result = await _useCase(repository, remote).execute();

    expect(
      result.states[BattleStatsContentType.abyss],
      RemoteBattleStatsState.unsupportedSchema,
    );
    expect(remote.bundleCalls, 0);
    expect(repository.replaced, isEmpty);
    expect(repository.etag, isNull);
  });

  test(
    'repository transaction failure leaves the old bundle selected',
    () async {
      final repository =
          _FakeRepository()
            ..storedBundle = _bundle()
            ..failReplace = true;
      final remote = _FakeRemote(_manifest(), pages: [_page()]);
      final result = await _useCase(repository, remote).execute();

      expect(
        result.states[BattleStatsContentType.abyss],
        RemoteBattleStatsState.invalid,
      );
      expect(repository.storedBundle?.revision, 1);
    },
  );
}

final _item = BattleStatsManifestItem(
  contentType: BattleStatsContentType.abyss,
  seasonId: 'season',
  revision: 2,
  payloadHash: 'sha256:$_zeros',
  updatedAt: _date,
);
final _date = DateTime.utc(2026, 7, 24);
const _zeros =
    '0000000000000000000000000000000000000000000000000000000000000000';

BattleStatsManifest _manifest() => BattleStatsManifest(
  schemaVersion: 1,
  items: {BattleStatsContentType.abyss: _item},
  etag: '"fixture"',
);

BattleStatsBundlePage _page({int page = 0, int pageCount = 1}) {
  return BattleStatsBundlePage(
    schemaVersion: 1,
    contentType: BattleStatsContentType.abyss,
    sourceVersion: 'fixture-1',
    seasonId: 'season',
    revision: 2,
    payloadHash: 'sha256:$_zeros',
    sourceUpdatedAt: _date,
    page: page,
    pageCount: pageCount,
    teams: [
      RemoteBattleTeam(
        teamKey: '10000001:10000002:10000003:10000004',
        members: const ['10000001', '10000002', '10000003', '10000004'],
        usageRate: page == 0 ? 0.5 : 0.25,
        side: page == 0 ? 'upper' : 'lower',
      ),
    ],
    characters: [
      RemoteBattleCharacterUsage(
        characterId: page == 0 ? '10000001' : '10000002',
        usageRate: 0.5,
      ),
    ],
  );
}

BattleStatsBundle _bundle() => BattleStatsBundle(
  schemaVersion: 1,
  contentType: BattleStatsContentType.abyss,
  sourceVersion: 'fixture-1',
  seasonId: 'old',
  revision: 1,
  payloadHash: 'sha256:$_zeros',
  sourceUpdatedAt: _date,
  teams: const [],
  characters: const [],
);

SyncBattleStatisticsUseCase _useCase(
  _FakeRepository repository,
  _FakeRemote remote, {
  BattleStatsIntegrityVerifier verifier = const _Verifier(true),
}) {
  return SyncBattleStatisticsUseCase(
    remote: remote,
    repository: repository,
    characterRepository: _FakeCharacterRepository(),
    integrityVerifier: verifier,
  );
}

class _FakeRemote implements BattleStatisticsRemoteSource {
  _FakeRemote(this.manifest, {this.pages = const []});

  final BattleStatsManifest manifest;
  final List<BattleStatsBundlePage> pages;
  var bundleCalls = 0;
  var failManifest = false;

  @override
  Future<BattleStatsManifestFetchResult> fetchManifest({String? etag}) async {
    if (failManifest) throw const FormatException('offline');
    return BattleStatsManifestFetchResult(
      notModified: false,
      manifest: manifest,
    );
  }

  @override
  Future<BattleStatsBundlePage> fetchBundlePage({
    required BattleStatsContentType contentType,
    required int revision,
    required int page,
  }) async {
    bundleCalls++;
    return pages[page];
  }
}

class _FakeRepository implements BattleStatisticsRepository {
  final manifests = <BattleStatsContentType, BattleStatsManifestItem>{};
  final replaced = <BattleStatsBundle>[];
  BattleStatsBundle? storedBundle;
  String? etag;
  bool failReplace = false;

  @override
  Future<BattleStatsManifestItem?> readManifest(
    BattleStatsContentType type,
  ) async => manifests[type];

  @override
  Future<String?> readManifestEtag() async => etag;

  @override
  Future<void> writeManifestEtag(String value) async => etag = value;

  @override
  Future<void> replaceBundle(BattleStatsBundle bundle) async {
    if (failReplace) throw const FormatException('transaction failed');
    replaced.add(bundle);
    storedBundle = bundle;
    manifests[bundle.contentType] = BattleStatsManifestItem(
      contentType: bundle.contentType,
      seasonId: bundle.seasonId,
      revision: bundle.revision,
      payloadHash: bundle.payloadHash,
      updatedAt: bundle.sourceUpdatedAt,
    );
  }

  @override
  Future<List<RemoteBattleTeam>> readTeams(BattleStatsContentType type) async =>
      storedBundle?.teams ?? const [];

  @override
  Future<void> recordSyncState(
    BattleStatsContentType type,
    RemoteBattleStatsState state, {
    String? errorCode,
  }) async {}
}

class _FakeCharacterRepository implements CharacterRepository {
  @override
  Future<List<MasterCharacter>> getAll() async => [
    for (var index = 1; index <= 4; index++)
      MasterCharacter(
        id: '1000000$index',
        name: 'キャラ$index',
        element: 'pyro',
        weaponType: 'sword',
        rarity: 5,
        region: 'test',
        iconUrl: '',
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Verifier implements BattleStatsIntegrityVerifier {
  const _Verifier(this.value);

  final bool value;

  @override
  bool matches(BattleStatsBundle bundle) => value;
}
