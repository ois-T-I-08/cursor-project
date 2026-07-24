import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/team_recommendations/normalize_simulation_builds.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';

void main() {
  const character = MasterCharacter(
    id: '10000089',
    name: 'フリーナ',
    element: 'hydro',
    weaponType: 'sword',
    rarity: 5,
    region: 'Fontaine',
    iconUrl: '',
  );

  test('HoYoLAB build is reduced to normalized combat data only', () {
    const build = HoyolabCharacterBuild(
      id: '10000089',
      isOwned: true,
      level: 90,
      promoteLevel: 6,
      constellation: 1,
      talents: [
        GameRecordTalent(name: '通常攻撃', level: 6),
        GameRecordTalent(name: '元素スキル', level: 9),
        GameRecordTalent(name: '元素爆発', level: 10),
      ],
      weapon: GameRecordWeapon(
        id: '11513',
        name: '静水流転の輝き',
        level: 90,
        refinement: 1,
        promoteLevel: 6,
      ),
      relics: [
        GameRecordRelic(
          id: '1',
          name: '花',
          posName: '生の花',
          level: 20,
          setName: '黄金の劇団',
          mainStat: GameRecordProp(label: 'HP', value: '4780'),
          subStats: [GameRecordProp(label: '会心率', value: '3.9%')],
        ),
      ],
    );
    final result = normalizeSimulationBuilds(
      characters: const [character],
      hoyolabBuilds: const {'10000089': build},
      localProgress: const {},
    );
    final snapshot = result.single;
    expect(snapshot.level, 90);
    expect(snapshot.talents, {'normal': 6, 'skill': 9, 'burst': 10});
    expect(snapshot.weapon?['weaponId'], '11513');
    expect((snapshot.artifacts?['stats'] as Map)['hpFlat'], 4780);
    expect((snapshot.artifacts?['sets'] as List), isEmpty);
    expect(snapshot.inputQuality, SimulationInputQuality.partial);
    expect(snapshot.defaultedFields, contains('artifactSets'));
    final encoded = jsonEncode(snapshot.toJson()).toLowerCase();
    expect(encoded, isNot(contains('cookie')));
    expect(encoded, isNot(contains('uid')));
    expect(encoded, isNot(contains('account')));
  });

  test('missing character data is explicit unsupported instead of guessed', () {
    final snapshot =
        normalizeSimulationBuilds(
          characters: const [character],
          hoyolabBuilds: const {},
          localProgress: const {},
        ).single;
    expect(snapshot.isOwned, isFalse);
    expect(snapshot.inputQuality, SimulationInputQuality.unsupported);
    expect(
      snapshot.defaultedFields,
      containsAll(['talents', 'weapon', 'artifacts']),
    );
  });

  test('traveler composite ids and invalid elements are dropped', () {
    const traveler = MasterCharacter(
      id: '10000005-anemo',
      name: '旅人',
      element: 'anemo',
      weaponType: 'sword',
      rarity: 5,
      region: '',
      iconUrl: '',
    );
    const badElement = MasterCharacter(
      id: '10000002',
      name: 'Unknown',
      element: 'None',
      weaponType: 'sword',
      rarity: 5,
      region: '',
      iconUrl: '',
    );
    final result = normalizeSimulationBuilds(
      characters: const [character, traveler, badElement],
      hoyolabBuilds: const {},
      localProgress: const {},
    );
    expect(result.map((value) => value.characterId), ['10000089']);
  });

  test('invalid weapon ids are omitted instead of failing the request', () {
    const build = HoyolabCharacterBuild(
      id: '10000089',
      isOwned: true,
      level: 90,
      promoteLevel: 6,
      constellation: 0,
      talents: [
        GameRecordTalent(name: '通常攻撃', level: 1),
        GameRecordTalent(name: '元素スキル', level: 1),
        GameRecordTalent(name: '元素爆発', level: 1),
      ],
      weapon: GameRecordWeapon(
        id: 'weapon-foo',
        name: 'x',
        level: 90,
        refinement: 1,
        promoteLevel: 6,
      ),
      relics: [],
    );
    final snapshot = normalizeSimulationBuilds(
      characters: const [character],
      hoyolabBuilds: const {'10000089': build},
      localProgress: const {},
    ).single;
    expect(snapshot.weapon, isNull);
    expect(snapshot.defaultedFields, contains('weapon'));
  });
}
