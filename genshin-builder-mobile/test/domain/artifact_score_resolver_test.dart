import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_type_override_registry.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight_repository.dart';
import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight_source.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';
import 'package:genshin_builder_mobile/domain/artifact_score_resolver.dart';

void main() {
  setUp(() {
    ArtifactScoreTypeOverrideRegistry.instance.useOverridesForTest({
      '胡桃': ArtifactScoreType.hp,
      '雷電将軍': ArtifactScoreType.recharge,
    });
  });

  tearDown(() {
    ArtifactScoreTypeOverrideRegistry.instance.resetForTest();
  });

  test('resolver prefers user override over weight profile', () async {
    final source = _FakeSource([
      ArtifactScoreWeightProfile(
        characterId: '10000046',
        name: '胡桃',
        weights: scoreWeightsForType(ArtifactScoreType.hp),
      ),
    ]);
    final resolver = ArtifactScoreResolver(ArtifactScoreWeightRepository(source));

    final settings = await resolver.resolve(
      character: const MasterCharacter(
        id: '10000046',
        name: '胡桃',
        element: 'Pyro',
        weaponType: 'polearm',
        rarity: 5,
        region: 'liyue',
        iconUrl: '',
      ),
      userScoreType: ArtifactScoreType.atk,
      userScoreTypeIsSet: true,
    );

    expect(settings.scoreType, ArtifactScoreType.atk);
    expect(settings.weights, scoreWeightsForType(ArtifactScoreType.atk));
    expect(settings.usesCustomWeights, isFalse);
  });

  test('resolver uses weight profile when user override is absent', () async {
    final source = _FakeSource([
      ArtifactScoreWeightProfile(
        characterId: '10000052',
        name: '雷電将軍',
        weights: scoreWeightsForType(ArtifactScoreType.recharge),
      ),
    ]);
    final resolver = ArtifactScoreResolver(ArtifactScoreWeightRepository(source));

    final settings = await resolver.resolve(
      character: const MasterCharacter(
        id: '10000052',
        name: '雷電将軍',
        element: 'Electro',
        weaponType: 'polearm',
        rarity: 5,
        region: 'inazuma',
        iconUrl: '',
        scoreType: 'atk',
      ),
    );

    expect(settings.scoreType, ArtifactScoreType.recharge);
    expect(settings.weights, scoreWeightsForType(ArtifactScoreType.recharge));
  });
}

class _FakeSource implements ArtifactScoreWeightSource {
  _FakeSource(this._profiles);

  final List<ArtifactScoreWeightProfile> _profiles;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() async => _profiles;
}
