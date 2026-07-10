import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/amber/amber_master_parsers.dart';

void main() {
  group('parseCharactersFromAmberItems', () {
    test('maps element, traveler display name, and scoreType', () {
      final characters = parseCharactersFromAmberItems({
        'a': {
          'id': 10000042,
          'name': '刻晴',
          'element': 'Electric',
          'weaponType': 'WEAPON_SWORD_ONE_HAND',
          'rank': 5,
          'region': 'Liyue',
          'icon': 'UI_AvatarIcon_Keqing',
          'specialProp': 'FIGHT_PROP_CRITICAL',
        },
        't': {
          'id': '10000005-anemo',
          'name': '旅人',
          'element': 'Wind',
          'weaponType': 'WEAPON_SWORD_ONE_HAND',
          'rank': 5,
          'region': '',
          'icon': 'UI_AvatarIcon_PlayerBoy',
          'specialProp': 'FIGHT_PROP_ATTACK_PERCENT',
        },
        'skip': {
          'id': '10000007-anemo',
          'name': '旅人',
          'element': 'Wind',
          'weaponType': 'WEAPON_SWORD_ONE_HAND',
          'rank': 5,
          'region': '',
          'icon': 'x',
          'specialProp': 'FIGHT_PROP_ATTACK_PERCENT',
        },
        'em': {
          'id': 10000006,
          'name': 'Lisa',
          'element': 'Electric',
          'weaponType': 'WEAPON_CATALYST',
          'rank': 4,
          'region': 'Mondstadt',
          'icon': 'UI_AvatarIcon_Lisa',
          'specialProp': 'FIGHT_PROP_ELEMENT_MASTERY',
        },
      });

      expect(characters.map((c) => c.id), isNot(contains('10000007-anemo')));
      final keqing = characters.firstWhere((c) => c.id == '10000042');
      expect(keqing.name, '刻晴');
      expect(keqing.element, 'electro');
      expect(keqing.scoreType, 'atk');

      final traveler = characters.firstWhere((c) => c.id.startsWith('10000005-'));
      expect(traveler.name, contains('旅人'));
      expect(traveler.element, 'anemo');

      final lisa = characters.firstWhere((c) => c.id == '10000006');
      expect(lisa.rarity, 4);
      expect(lisa.scoreType, 'em');
    });

    test('applies name override storage', () {
      final characters = parseCharactersFromAmberItems(
        {
          'h': {
            'id': 10000046,
            'name': '胡桃',
            'element': 'Fire',
            'weaponType': 'WEAPON_POLE',
            'rank': 5,
            'region': 'Liyue',
            'icon': 'UI_AvatarIcon_Hutao',
            'specialProp': 'FIGHT_PROP_ATTACK_PERCENT',
          },
        },
        nameOverrideStorage: const {'胡桃': 'hp'},
      );
      expect(characters.single.scoreType, 'hp');
    });
  });

  group('parseWeaponsFromAmberItems', () {
    test('maps weapon fields', () {
      final weapons = parseWeaponsFromAmberItems({
        'w': {
          'id': 11509,
          'name': '霧切の廻光',
          'type': 'WEAPON_SWORD_ONE_HAND',
          'rank': 5,
          'icon': 'UI_EquipIcon_Sword_Narukami',
        },
      });
      expect(weapons.single.name, '霧切の廻光');
      expect(weapons.single.weaponType, 'sword');
      expect(weapons.single.rarity, 5);
    });
  });

  group('parseMaterialsFromAmberItems', () {
    test('uses map key as id', () {
      final materials = parseMaterialsFromAmberItems({
        '104301': {
          'name': '「自由」の教え',
          'type': 'MATERIAL_AVATAR_MATERIAL',
          'rank': 2,
          'icon': 'UI_ItemIcon_104301',
        },
      });
      expect(materials.single.id, '104301');
      expect(materials.single.name, '「自由」の教え');
    });
  });
}
