import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/character_list_sort.dart';

void main() {
  group('character list sort', () {
    test('owned characters appear before unowned', () {
      final characters = [
        const MasterCharacter(
          id: '10000002',
          name: '綾華',
          element: 'cryo',
          weaponType: 'sword',
          rarity: 5,
          region: '稲妻',
          iconUrl: '',
        ),
        const MasterCharacter(
          id: '10000003',
          name: '未所持',
          element: 'pyro',
          weaponType: 'polearm',
          rarity: 5,
          region: 'モンド',
          iconUrl: '',
        ),
      ];
      final ownedMap = {
        '10000002': const HoyolabOwnedCharacter(
          id: '10000002',
          name: '綾華',
          level: 90,
        ),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
      );

      expect(entries.first.isOwned, isTrue);
      expect(entries.last.isOwned, isFalse);
    });

    test('traveler id matches base id without element suffix', () {
      final characters = [
        const MasterCharacter(
          id: '10000005-anemo',
          name: '旅人（風）',
          element: 'anemo',
          weaponType: 'sword',
          rarity: 5,
          region: 'その他',
          iconUrl: '',
        ),
      ];
      final ownedMap = {
        '10000005': const HoyolabOwnedCharacter(
          id: '10000005',
          name: '旅人',
          level: 90,
        ),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
      );

      expect(entries.single.isOwned, isTrue);
    });
  });
}
