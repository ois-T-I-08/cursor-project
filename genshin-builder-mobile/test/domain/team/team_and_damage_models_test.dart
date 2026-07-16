import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/damage/damage_context.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/team/team_models.dart';

void main() {
  test('Team isFull at 4 members', () {
    final team = Team(
      id: 't1',
      name: 'Test',
      members: [
        for (var i = 0; i < 4; i++)
          TeamMemberSlot(characterId: 'c$i', position: i),
      ],
    );
    expect(team.isFull, isTrue);
    expect(team.size, 4);
  });

  test('estimateDamage returns placeholder notes', () {
    const character = MasterCharacter(
      id: '10000046',
      name: '胡桃',
      element: 'pyro',
      weaponType: 'polearm',
      rarity: 5,
      region: '璃月',
      iconUrl: '',
    );
    final result = estimateDamage(const DamageContext(character: character, level: 90));
    expect(result.average, 0);
    expect(result.notes, isNotEmpty);
  });
}
