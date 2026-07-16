
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight_repository.dart';
import 'package:genshin_builder_mobile/data/artifact_score/local_json_artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.content);

  final String content;

  @override
  Future<ByteData> load(String key) async => ByteData(0);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => content;
}

void main() {
  test('loads and finds profile by character id', () async {
    const json = '''
{
  "profiles": [
    {
      "characterId": "10000052",
      "name": "雷電将軍",
      "weights": {
        "critRate": 2,
        "critDamage": 1,
        "atkPercent": 0,
        "hpPercent": 0,
        "defPercent": 0,
        "elementalMastery": 0,
        "energyRecharge": 1
      }
    }
  ]
}
''';
    final repo = ArtifactScoreWeightRepository(
      LocalJsonArtifactScoreWeightSource(
        bundle: _FakeAssetBundle(json),
        assetPath: 'dummy.json',
      ),
    );

    final profile = await repo.findByCharacterId('10000052');
    expect(profile, isNotNull);
    expect(profile!.name, '雷電将軍');
    expect(profile.weights.energyRecharge, 1);
  });

  test('returns null for unknown character id', () async {
    const json = '''
{
  "profiles": [
    {
      "characterId": "10000052",
      "name": "雷電将軍",
      "weights": { "critRate": 2 }
    }
  ]
}
''';
    final repo = ArtifactScoreWeightRepository(
      LocalJsonArtifactScoreWeightSource(
        bundle: _FakeAssetBundle(json),
        assetPath: 'dummy.json',
      ),
    );

    final profile = await repo.findByCharacterId('unknown');
    expect(profile, isNull);
  });

  test('syncMissingCharacterProfiles retries with refreshable source', () async {
    final source = _FakeRefreshableSource(
      initial: const [],
      refreshed: const [
        ArtifactScoreWeightProfile(
          characterId: '10000052',
          name: '雷電将軍',
          weights: ArtifactStatWeights(
            critRate: 2,
            critDamage: 1,
            atkPercent: 0,
            hpPercent: 0,
            defPercent: 0,
            elementalMastery: 0,
            energyRecharge: 1,
          ),
        ),
      ],
    );
    final repo = ArtifactScoreWeightRepository(source);
    const characters = [
      MasterCharacter(
        id: '10000052',
        name: '雷電将軍',
        element: 'Electro',
        weaponType: 'polearm',
        rarity: 5,
        region: 'inazuma',
        iconUrl: '',
      ),
    ];
    final missing = await repo.syncMissingCharacterProfiles(characters);
    expect(missing, isEmpty);
    expect(source.refreshCalled, isTrue);
  });
}

class _FakeRefreshableSource implements RefreshableArtifactScoreWeightSource {
  _FakeRefreshableSource({required this.initial, required this.refreshed});

  final List<ArtifactScoreWeightProfile> initial;
  final List<ArtifactScoreWeightProfile> refreshed;
  bool refreshCalled = false;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() async => initial;

  @override
  Future<List<ArtifactScoreWeightProfile>> refreshProfiles() async {
    refreshCalled = true;
    return refreshed;
  }
}
