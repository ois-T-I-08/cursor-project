import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/character_list_sort.dart';

MasterCharacter _char({
  required String id,
  required String name,
  int rarity = 5,
  String element = 'pyro',
  String region = 'mondstadt',
}) =>
    MasterCharacter(
      id: id,
      name: name,
      element: element,
      weaponType: 'sword',
      rarity: rarity,
      region: region,
      iconUrl: '',
    );

OwnedCharacterSortInfo _owned({
  int level = 1,
  int constellation = 0,
  int friendship = 0,
  DateTime? obtainedAt,
}) =>
    OwnedCharacterSortInfo(
      level: level,
      constellation: constellation,
      friendship: friendship,
      obtainedAt: obtainedAt,
    );

void main() {
  group('character list sort', () {
    test('owned characters appear before unowned with default settings', () {
      final characters = [
        _char(id: '10000002', name: 'Ayaka'),
        _char(id: '10000003', name: 'Unowned'),
      ];
      final ownedMap = {
        '10000002': _owned(level: 90),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.ownedDefault,
          groupByOwnership: true,
        ),
      );

      expect(entries.first.isOwned, isTrue);
      expect(entries.last.isOwned, isFalse);
    });

    test('traveler id matches base id without element suffix', () {
      final characters = [
        _char(id: '10000005-anemo', name: 'TravelerAnemo', element: 'anemo'),
      ];
      final ownedMap = {
        '10000005': _owned(level: 90),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
      );

      expect(entries.single.isOwned, isTrue);
    });

    test('sorts by name ascending when group is off', () {
      final characters = [
        _char(id: '1', name: 'HuTao'),
        _char(id: '2', name: 'Ayaka'),
        _char(id: '3', name: 'Kaeya'),
      ];

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: const {},
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.nameAsc,
          groupByOwnership: false,
        ),
      );

      expect(entries.map((e) => e.character.name).toList(), [
        'Ayaka',
        'HuTao',
        'Kaeya',
      ]);
    });

    test('sorts by rarity descending', () {
      final characters = [
        _char(id: '1', name: 'A', rarity: 4),
        _char(id: '2', name: 'B', rarity: 5),
      ];

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: const {},
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.rarityDesc,
          groupByOwnership: false,
        ),
      );

      expect(entries.first.character.rarity, 5);
    });

    test('sorts owned entries by level within groups', () {
      final characters = [
        _char(id: '1', name: 'Low'),
        _char(id: '2', name: 'High'),
        _char(id: '3', name: 'Unowned'),
      ];
      final ownedMap = {
        '1': _owned(level: 40),
        '2': _owned(level: 90),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.levelDesc,
          groupByOwnership: true,
        ),
      );

      expect(entries[0].character.name, 'High');
      expect(entries[1].character.name, 'Low');
      expect(entries.last.isOwned, isFalse);
    });

    test('sorts by obtained date descending', () {
      final characters = [
        _char(id: '1', name: 'Old'),
        _char(id: '2', name: 'New'),
      ];
      final ownedMap = {
        '1': _owned(obtainedAt: DateTime(2024, 1, 1)),
        '2': _owned(obtainedAt: DateTime(2025, 1, 1)),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.obtainedDesc,
          groupByOwnership: false,
        ),
      );

      expect(entries.first.character.name, 'New');
      expect(entries.last.character.name, 'Old');
    });

    test('owned default puts dated characters before undated ones', () {
      final characters = [
        _char(id: '1', name: 'NoDate'),
        _char(id: '2', name: 'New'),
        _char(id: '3', name: 'Old'),
      ];
      final ownedMap = {
        '1': _owned(level: 90),
        '2': _owned(obtainedAt: DateTime(2025, 1, 1)),
        '3': _owned(obtainedAt: DateTime(2024, 1, 1)),
      };

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: ownedMap,
        settings: const CharacterListSortSettings(
          mode: CharacterListSortMode.ownedDefault,
          groupByOwnership: true,
        ),
      );

      // ascending obtainedAt: older dated first, then undated
      expect(entries[0].character.name, 'Old');
      expect(entries[1].character.name, 'New');
      expect(entries[2].character.name, 'NoDate');
    });

    test('CharacterListSortMode.fromStorage falls back safely', () {
      expect(
        CharacterListSortModeLabels.fromStorage('nameAsc'),
        CharacterListSortMode.nameAsc,
      );
      expect(
        CharacterListSortModeLabels.fromStorage('invalid'),
        CharacterListSortMode.region,
      );
      expect(
        CharacterListSortModeLabels.fromStorage(null),
        CharacterListSortMode.region,
      );
    });

    test('groups by region in artifact order', () {
      final characters = [
        _char(id: '1', name: '香菱', region: '璃月', rarity: 4),
        _char(id: '2', name: 'ジン', region: 'モンド', rarity: 5),
        _char(id: '3', name: '雷電将軍', region: '稲妻', rarity: 5),
        _char(id: '4', name: 'バーバラ', region: 'モンド', rarity: 4),
      ];

      final entries = buildCharacterListEntries(
        characters: characters,
        ownedMap: const {},
      );
      final sections = groupCharacterEntriesByRegion(entries);

      expect(sections.map((s) => s.region).toList(), ['モンド', '璃月', '稲妻']);
      expect(sections[0].items.map((e) => e.character.name).toList(), [
        'ジン',
        'バーバラ',
      ]);
    });

    test('maps skirk to natlan and sandrone to nod-krai; drops fatui section', () {
      final characters = [
        _char(id: '10000114', name: 'スカーク', region: 'ファデュイ', rarity: 5),
        _char(id: '9', name: 'サンドローネ', region: 'ファデュイ', rarity: 5),
        _char(id: '10000033', name: 'タルタリヤ', region: 'ファデュイ', rarity: 5),
        _char(id: '2', name: 'ジン', region: 'モンド', rarity: 5),
      ];

      final sections = groupCharacterEntriesByRegion(
        buildCharacterListEntries(
          characters: characters,
          ownedMap: const {},
        ),
      );

      expect(sections.map((s) => s.region), isNot(contains('ファデュイ')));
      expect(
        sections.firstWhere((s) => s.region == 'ナタ').items.single.character.name,
        'スカーク',
      );
      expect(
        sections
            .firstWhere((s) => s.region == 'ノド・クライ')
            .items
            .single
            .character
            .name,
        'サンドローネ',
      );
      // タルタリヤは ID オーバーライドで璃月に移動
      expect(
        sections
            .firstWhere((s) => s.region == '璃月')
            .items
            .map((e) => e.character.name),
        contains('タルタリヤ'),
      );
    });

    test('traveler pinned before mondstadt section, all element variants shown', () {
      final characters = [
        _char(
          id: '10000005-anemo',
          name: '旅人（風）',
          region: 'モンド',
          rarity: 5,
        ),
        _char(
          id: '10000005-geo',
          name: '旅人（岩）',
          region: 'モンド',
          rarity: 5,
        ),
        _char(id: '2', name: 'ジン', region: 'モンド', rarity: 5),
        _char(id: '3', name: '香菱', region: '璃月', rarity: 4),
      ];

      final sections = groupCharacterEntriesByRegion(
        buildCharacterListEntries(
          characters: characters,
          ownedMap: const {},
        ),
      );

      // 先頭セクションが旅人
      expect(sections.first.region, '旅人');
      // 旅人セクションは元素ごとに全件表示
      expect(sections.first.items.length, 2);
      expect(
        sections.first.items.map((e) => e.character.name),
        containsAll(['旅人（風）', '旅人（岩）']),
      );
      // 2番目がモンド（旅人を含まない）
      expect(sections[1].region, 'モンド');
      expect(
        sections[1].items.map((e) => e.character.name),
        contains('ジン'),
      );
      expect(
        sections[1].items.map((e) => e.character.name),
        isNot(contains('旅人')),
      );
    });

    test('traveler from other region still pinned before mondstadt', () {
      final characters = [
        _char(
          id: '10000005-anemo',
          name: '旅人（風）',
          region: 'メイン大陸',
          rarity: 5,
        ),
        _char(id: '2', name: 'ジン', region: 'モンド', rarity: 5),
      ];

      final sections = groupCharacterEntriesByRegion(
        buildCharacterListEntries(
          characters: characters,
          ownedMap: const {},
        ),
      );

      expect(sections.first.region, '旅人');
      expect(sections.first.items.single.character.name, '旅人（風）');
      expect(sections[1].region, 'モンド');
    });
  });
}
