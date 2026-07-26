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

  test('skips non-numeric ids and drops invalid weapons', () {
    const traveler = MasterCharacter(
      id: '10000005-anemo',
      name: '旅人',
      element: 'anemo',
      weaponType: 'sword',
      rarity: 5,
      region: 'Mondstadt',
      iconUrl: '',
    );
    const build = HoyolabCharacterBuild(
      id: '10000089',
      isOwned: true,
      level: 90,
      promoteLevel: 6,
      constellation: 0,
      weapon: GameRecordWeapon(
        id: 'not-a-weapon-id',
        name: 'x',
        level: 90,
        refinement: 0,
        promoteLevel: 6,
      ),
    );
    final result = normalizeSimulationBuilds(
      characters: const [character, traveler],
      hoyolabBuilds: const {'10000089': build},
      localProgress: const {},
    );
    expect(result.map((value) => value.characterId), ['10000089']);
    expect(result.single.weapon?['weaponId'], '11401');
    expect(result.single.defaultedFields, contains('weapon'));
    expect(result.single.inputQuality, SimulationInputQuality.defaulted);
  });

  test('owned incomplete builds get documented talent/weapon defaults', () {
    const build = HoyolabCharacterBuild(
      id: '10000089',
      isOwned: true,
      level: 90,
      promoteLevel: 6,
      constellation: 0,
    );
    final snapshot =
        normalizeSimulationBuilds(
          characters: const [character],
          hoyolabBuilds: const {'10000089': build},
          localProgress: const {},
        ).single;
    expect(snapshot.talents, {'normal': 1, 'skill': 1, 'burst': 1});
    expect(snapshot.weapon?['weaponId'], '11401');
    expect(snapshot.defaultedFields, containsAll(['talents', 'weapon']));
    expect(snapshot.inputQuality, SimulationInputQuality.defaulted);
  });
}
