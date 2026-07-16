import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/artifact_score/composite_artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/artifact_score/local_json_artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/config/config_load_log.dart';
import 'package:genshin_builder_mobile/data/config/remote_json_fetch.dart';
import 'package:genshin_builder_mobile/data/daily_materials/composite_daily_material_schedule_source.dart';
import 'package:genshin_builder_mobile/data/daily_materials/daily_material_schedule_repository.dart';
import 'package:genshin_builder_mobile/data/gacha/asset_gacha_banner_history_source.dart';
import 'package:genshin_builder_mobile/data/gacha/gacha_banner_repository.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/gacha/gacha_banner_schedule.dart';

class _MemBundle extends CachingAssetBundle {
  _MemBundle(this._files);
  final Map<String, String> _files;

  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('unexpected binary load $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final v = _files[key];
    if (v == null) throw FlutterError('missing $key');
    return v;
  }
}

class _FakeWeightRemote implements RefreshableArtifactScoreWeightSource {
  _FakeWeightRemote(this._impl);
  final Future<List<ArtifactScoreWeightProfile>> Function() _impl;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() => _impl();

  @override
  Future<List<ArtifactScoreWeightProfile>> refreshProfiles() => _impl();
}

class _FakeSchedule implements DailyMaterialScheduleSource {
  _FakeSchedule(this._impl);
  final Future<DailyMaterialSchedule> Function() _impl;

  @override
  Future<DailyMaterialSchedule> load() => _impl();
}

class _FakeHistory implements GachaBannerHistorySource {
  _FakeHistory(this._impl);
  final Future<GachaBannerSchedule> Function() _impl;

  @override
  Future<GachaBannerSchedule> load() => _impl();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> logs;

  setUp(() {
    logs = [];
    configLoadLogSink = logs.add;
  });

  tearDown(() {
    configLoadLogSink = null;
  });

  group('bundled assets pass validators', () {
    test('artifact_score_weights.json', () async {
      final source = LocalJsonArtifactScoreWeightSource();
      final profiles = await source.loadProfiles();
      expect(profiles, isNotEmpty);
    });

    test('daily_material_schedule.json', () async {
      final source = LocalJsonDailyMaterialScheduleSource();
      final schedule = await source.load();
      expect(schedule.version, greaterThan(0));
      expect(schedule.talentSeries, isNotEmpty);
    });

    test('gacha_banner_history.json', () async {
      final source = AssetGachaBannerHistorySource();
      final schedule = await source.load();
      expect(schedule.banners.length, greaterThan(100));
    });
  });

  group('weights composite', () {
    test('remote schema failure falls back to local with one log', () async {
      final local = LocalJsonArtifactScoreWeightSource(
        bundle: _MemBundle({
          'assets/config/artifact_score_weights.json': jsonEncode({
            'profiles': [
              {
                'characterId': 'local1',
                'name': 'L',
                'weights': {'critRate': 1},
              },
            ],
          }),
        }),
      );
      final remote = _FakeWeightRemote(() async {
        throw configLoadFromFormatException(
          kind: 'artifact_score_weights',
          error: const FormatException('profiles'),
        );
      });
      final composite = CompositeArtifactScoreWeightSource(
        localSource: local,
        remoteSource: remote,
      );
      final profiles = await composite.loadProfiles();
      expect(profiles.single.characterId, 'local1');
      expect(logs.where((l) => l.contains('result=fallback')), hasLength(1));
      expect(logs.single, contains('kind=artifact_score_weights'));
      expect(logs.single, isNot(contains('http')));
      expect(logs.single, isNot(contains('token')));
    });

    test('invalid remote does not destroy valid cache', () async {
      var remoteCalls = 0;
      final local = LocalJsonArtifactScoreWeightSource(
        bundle: _MemBundle({
          'assets/config/artifact_score_weights.json': jsonEncode({
            'profiles': [
              {
                'characterId': 'c1',
                'weights': {'critRate': 1},
              },
            ],
          }),
        }),
      );
      final remote = _FakeWeightRemote(() async {
        remoteCalls++;
        if (remoteCalls == 1) {
          return [
            ArtifactScoreWeightProfile(
              characterId: 'c1',
              name: 'R',
              weights: ArtifactStatWeights.fromJson(const {'critRate': 2}),
            ),
          ];
        }
        throw const RemoteJsonFetchException(
          kind: 'artifact_score_weights',
          failure: RemoteJsonFailureKind.timeout,
        );
      });
      final composite = CompositeArtifactScoreWeightSource(
        localSource: local,
        remoteSource: remote,
        refreshInterval: Duration.zero,
      );
      final first = await composite.loadProfiles();
      expect(first, isNotEmpty);
      final second = await composite.loadProfiles();
      expect(second, isNotEmpty);
    });
  });

  group('daily composite', () {
    test('remote failure falls back to local', () async {
      final local = _FakeSchedule(() async => const DailyMaterialSchedule(
            version: 1,
            talentSeries: [
              DailyMaterialSeries(
                id: 't',
                name: 't',
                region: 'r',
                kind: DailyMaterialKind.talentBook,
                days: [1],
                materialIds: ['1'],
              ),
            ],
            weaponSeries: [
              DailyMaterialSeries(
                id: 'w',
                name: 'w',
                region: 'r',
                kind: DailyMaterialKind.weaponAscension,
                days: [1],
                materialIds: ['2'],
              ),
            ],
          ));
      final remote = _FakeSchedule(() async {
        throw const RemoteJsonFetchException(
          kind: 'daily_material_schedule',
          failure: RemoteJsonFailureKind.timeout,
        );
      });
      final composite = CompositeDailyMaterialScheduleSource(
        localSource: local,
        remoteSource: remote,
      );
      final got = await composite.load();
      expect(got.version, 1);
      expect(logs.where((l) => l.contains('fallback')), hasLength(1));
      expect(logs.single, contains('reason=timeout'));
    });
  });

  group('prefer remote gacha', () {
    test('remote failure uses local and logs once', () async {
      final remote = _FakeHistory(() async {
        throw const RemoteJsonFetchException(
          kind: 'gacha_banner_history',
          failure: RemoteJsonFailureKind.httpStatus,
          statusCode: 500,
        );
      });
      final local = _FakeHistory(() async {
        return const GachaBannerSchedule(
          version: 1,
          banners: [],
        );
      });
      final source = PreferRemoteGachaBannerHistorySource(
        remote: remote,
        fallback: local,
      );
      final schedule = await source.load();
      expect(schedule.banners, isEmpty);
      expect(logs.where((l) => l.contains('fallback')), hasLength(1));
      expect(logs.single, contains('status=500'));
      expect(logs.single, isNot(contains('cookie')));
    });

    test('both fail logs fallback then local failed', () async {
      final remote = _FakeHistory(() async {
        throw const RemoteJsonFetchException(
          kind: 'gacha_banner_history',
          failure: RemoteJsonFailureKind.networkError,
        );
      });
      final local = _FakeHistory(() async {
        throw const ConfigLoadException(
          kind: 'gacha_banner_history',
          failure: ConfigLoadFailureKind.invalidJson,
        );
      });
      final source = PreferRemoteGachaBannerHistorySource(
        remote: remote,
        fallback: local,
      );
      await expectLater(source.load(), throwsA(isA<ConfigLoadException>()));
      expect(logs.where((l) => l.contains('result=fallback')), hasLength(1));
      expect(logs.where((l) => l.contains('result=failed')), hasLength(1));
    });
  });

  group('local invalid', () {
    test('weights invalid root', () async {
      final source = LocalJsonArtifactScoreWeightSource(
        bundle: _MemBundle({
          'assets/config/artifact_score_weights.json': '[1]',
        }),
      );
      await expectLater(
        source.loadProfiles(),
        throwsA(
          isA<ConfigLoadException>().having(
            (e) => e.failure,
            'failure',
            ConfigLoadFailureKind.invalidRootType,
          ),
        ),
      );
    });

    test('weights schema invalid', () async {
      final source = LocalJsonArtifactScoreWeightSource(
        bundle: _MemBundle({
          'assets/config/artifact_score_weights.json': jsonEncode({
            'profiles': [
              {'characterId': '', 'weights': {}},
            ],
          }),
        }),
      );
      await expectLater(
        source.loadProfiles(),
        throwsA(isA<ConfigLoadException>()),
      );
    });
  });
}
