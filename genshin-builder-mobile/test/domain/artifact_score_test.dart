import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';

const _sampleNameOverrides = <String, ArtifactScoreType>{
  '鍾離': ArtifactScoreType.hp,
  'コロンビーナ': ArtifactScoreType.hp,
  '雷電将軍': ArtifactScoreType.recharge,
  '楓原万葉': ArtifactScoreType.em,
  '胡桃': ArtifactScoreType.hp,
};

void main() {
  test('piece score formula for each score type', () {
    const piece = ArtifactPiece(
      substats: [
        ArtifactSubstat(stat: '会心ダメージ', value: 20),
        ArtifactSubstat(stat: '会心率', value: 10),
        ArtifactSubstat(stat: '攻撃力%', value: 10),
        ArtifactSubstat(stat: '元素熟知', value: 40),
      ],
    );

    expect(calcArtifactPieceScore(piece, ArtifactScoreType.atk), 50);
    expect(calcArtifactPieceScore(piece, ArtifactScoreType.hp), 40);
    expect(calcArtifactPieceScore(piece, ArtifactScoreType.def), 40);
    expect(calcArtifactPieceScore(piece, ArtifactScoreType.recharge), 40);
    expect(calcArtifactPieceScore(piece, ArtifactScoreType.em), 50);
  });

  test('infer score type from specialProp and name map', () {
    expect(
      inferScoreType('FIGHT_PROP_ELEMENT_MASTERY', 'リサ'),
      ArtifactScoreType.em,
    );
    expect(
      inferScoreType('FIGHT_PROP_CHARGE_EFFICIENCY', 'ガイア'),
      ArtifactScoreType.recharge,
    );
    expect(
      inferScoreType(
        'FIGHT_PROP_ROCK_ADD_HURT',
        '鍾離',
        nameOverrides: _sampleNameOverrides,
      ),
      ArtifactScoreType.hp,
    );
    expect(
      inferScoreType(
        'FIGHT_PROP_CRITICAL',
        'コロンビーナ',
        nameOverrides: _sampleNameOverrides,
      ),
      ArtifactScoreType.hp,
    );
    expect(
      inferScoreType(
        'FIGHT_PROP_CHARGE_EFFICIENCY',
        '雷電将軍',
        nameOverrides: _sampleNameOverrides,
      ),
      ArtifactScoreType.recharge,
    );
  });

  test('resolve score type from character scoreType and fallback name map', () {
    const byDb = MasterCharacter(
      id: '1',
      name: 'テスト',
      element: 'Pyro',
      weaponType: 'sword',
      rarity: 5,
      region: 'mondstadt',
      iconUrl: '',
      scoreType: 'recharge',
    );
    expect(resolveArtifactScoreType(byDb), ArtifactScoreType.recharge);

    const byName = MasterCharacter(
      id: '2',
      name: '楓原万葉',
      element: 'Anemo',
      weaponType: 'sword',
      rarity: 5,
      region: 'inazuma',
      iconUrl: '',
      scoreType: 'unknown',
    );
    expect(
      resolveArtifactScoreType(
        byName,
        nameOverrides: _sampleNameOverrides,
      ),
      ArtifactScoreType.em,
    );

    const genericAtk = MasterCharacter(
      id: '3',
      name: '胡桃',
      element: 'Pyro',
      weaponType: 'polearm',
      rarity: 5,
      region: 'liyue',
      iconUrl: '',
      scoreType: 'atk',
    );
    expect(
      resolveArtifactScoreType(
        genericAtk,
        nameOverrides: _sampleNameOverrides,
      ),
      ArtifactScoreType.hp,
    );
  });

  test('user score type storage uses user prefix', () {
    expect(
      userArtifactScoreTypeFromStorage('user:hp'),
      ArtifactScoreType.hp,
    );
    expect(userArtifactScoreTypeFromStorage('hp'), isNull);
    expect(userArtifactScoreTypeFromStorage('atk'), isNull);
    expect(
      artifactScoreTypeToUserStorage(ArtifactScoreType.recharge),
      'user:recharge',
    );
  });

  test('piece score can be calculated from explicit weights', () {
    const piece = ArtifactPiece(
      substats: [
        ArtifactSubstat(stat: '会心率', value: 10),
        ArtifactSubstat(stat: '会心ダメージ', value: 20),
        ArtifactSubstat(stat: '元素チャージ効率', value: 15),
      ],
    );
    const weights = ArtifactStatWeights(
      critRate: 2,
      critDamage: 1,
      atkPercent: 0,
      hpPercent: 0,
      defPercent: 0,
      elementalMastery: 0,
      energyRecharge: 1,
    );
    expect(calcArtifactPieceScoreWithWeights(piece, weights), 55);
  });

  test('infer score type from built-in weights', () {
    expect(
      inferArtifactScoreTypeFromWeights(scoreWeightsForType(ArtifactScoreType.hp)),
      ArtifactScoreType.hp,
    );
    expect(
      inferArtifactScoreTypeFromWeights(
        const ArtifactStatWeights(
          critRate: 2,
          critDamage: 1,
          atkPercent: 0.5,
          hpPercent: 0.5,
          defPercent: 0,
          elementalMastery: 0,
          energyRecharge: 0,
        ),
      ),
      isNull,
    );
  });
}
