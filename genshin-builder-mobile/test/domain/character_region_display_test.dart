import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/game_display.dart';

void main() {
  group('normalizeCharacterRegionForDisplay', () {
    test('skirk goes to natlan', () {
      expect(
        normalizeCharacterRegionForDisplay(
          'ファデュイ',
          characterId: '10000114',
          characterName: 'スカーク',
        ),
        'ナタ',
      );
    });

    test('sandrone goes to nod-krai by name', () {
      expect(
        normalizeCharacterRegionForDisplay(
          'FATUI',
          characterName: 'サンドローネ',
        ),
        'ノド・クライ',
      );
    });

    test('tartaglia goes to liyue by id override', () {
      expect(
        normalizeCharacterRegionForDisplay(
          'ファデュイ',
          characterId: '10000033',
          characterName: 'タルタリヤ',
        ),
        '璃月',
      );
    });

    test('other fatui go to other', () {
      expect(
        normalizeCharacterRegionForDisplay(
          'ファデュイ',
          characterName: '隊長',
        ),
        'その他',
      );
    });

    test('traveler goes to other', () {
      expect(
        normalizeCharacterRegionForDisplay('旅人', characterId: '10000005-anemo'),
        'その他',
      );
    });

    test('arlecchino goes to fontaine by id override', () {
      expect(
        normalizeCharacterRegionForDisplay(
          'ファデュイ',
          characterId: '10000096',
          characterName: 'Arlecchino',
        ),
        'フォンテーヌ',
      );
    });

    test('nico goes to nod-krai by name', () {
      expect(
        normalizeCharacterRegionForDisplay('', characterName: 'ニコ'),
        'ノド・クライ',
      );
      expect(
        normalizeCharacterRegionForDisplay('', characterName: 'Nico'),
        'ノド・クライ',
      );
    });

    test('shihaku goes to nod-krai by name', () {
      expect(
        normalizeCharacterRegionForDisplay('', characterName: '兹白'),
        'ノド・クライ',
      );
      expect(
        normalizeCharacterRegionForDisplay('', characterName: 'しはく'),
        'ノド・クライ',
      );
    });

    test('display order matches artifact regions', () {
      expect(gameRegionDisplayOrder, [
        'モンド',
        '璃月',
        '稲妻',
        'スメール',
        'フォンテーヌ',
        'ナタ',
        'ノド・クライ',
        'その他',
      ]);
      expect(gameRegionDisplayOrder, isNot(contains('ファデュイ')));
    });
  });
}
