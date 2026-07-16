import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/akasha/akasha_weapon_usage.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/weapon_list_sort.dart';

MasterWeapon _w({
  required String id,
  required String name,
  required int rarity,
  String type = 'sword',
}) =>
    MasterWeapon(
      id: id,
      name: name,
      weaponType: type,
      rarity: rarity,
      iconUrl: '',
    );

void main() {
  const character = MasterCharacter(
    id: '1',
    name: 'テスト',
    element: 'pyro',
    weaponType: 'sword',
    rarity: 5,
    region: 'モンド',
    iconUrl: '',
    scoreType: 'atk',
  );

  group('sortWeaponList', () {
    test('rarityDesc puts 5-star first', () {
      final entries = [
        WeaponListEntry(weapon: _w(id: 'a', name: 'A', rarity: 3)),
        WeaponListEntry(weapon: _w(id: 'b', name: 'B', rarity: 5)),
        WeaponListEntry(weapon: _w(id: 'c', name: 'C', rarity: 4)),
      ];
      final sorted = sortWeaponList(entries, WeaponListSortMode.rarityDesc);
      expect(sorted.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });

    test('baseAttackDesc sorts by attack', () {
      final entries = [
        WeaponListEntry(
          weapon: _w(id: 'a', name: 'A', rarity: 5),
          baseAttack: 500,
        ),
        WeaponListEntry(
          weapon: _w(id: 'b', name: 'B', rarity: 4),
          baseAttack: 600,
        ),
      ];
      final sorted =
          sortWeaponList(entries, WeaponListSortMode.baseAttackDesc);
      expect(sorted.first.id, 'b');
    });

    test('popularity prefers higher usage rate', () {
      final low = WeaponListEntry(
        weapon: _w(id: 'low', name: 'Low', rarity: 5),
        usageRate: 0.1,
        recommendScore: computeWeaponPopularityScore(
          usageRate: 0.1,
          rarity: 5,
        ),
      );
      final high = WeaponListEntry(
        weapon: _w(id: 'high', name: 'High', rarity: 4),
        usageRate: 0.45,
        recommendScore: computeWeaponPopularityScore(
          usageRate: 0.45,
          rarity: 4,
        ),
      );
      final sorted = sortWeaponList(
        [low, high],
        WeaponListSortMode.popularity,
      );
      expect(sorted.first.id, 'high');
    });

    test('heuristic fallback prefers matching substat and higher rarity', () {
      final low = WeaponListEntry(
        weapon: _w(id: 'low', name: 'Low', rarity: 4),
        specialProp: 'FIGHT_PROP_HP_PERCENT',
        recommendScore: computeWeaponRecommendScore(
          weapon: _w(id: 'low', name: 'Low', rarity: 4),
          character: character,
          specialProp: 'FIGHT_PROP_HP_PERCENT',
        ),
      );
      final high = WeaponListEntry(
        weapon: _w(id: 'high', name: 'High', rarity: 5),
        specialProp: 'FIGHT_PROP_ATTACK_PERCENT',
        recommendScore: computeWeaponRecommendScore(
          weapon: _w(id: 'high', name: 'High', rarity: 5),
          character: character,
          specialProp: 'FIGHT_PROP_ATTACK_PERCENT',
        ),
      );
      expect(high.recommendScore, greaterThan(low.recommendScore));
      final sorted = sortWeaponList(
        [low, high],
        WeaponListSortMode.popularity,
      );
      expect(sorted.first.id, 'high');
    });

    test('equipped weapon stays on top', () {
      final entries = [
        WeaponListEntry(weapon: _w(id: 'a', name: 'A', rarity: 5)),
        WeaponListEntry(weapon: _w(id: 'eq', name: 'Eq', rarity: 3)),
      ];
      final sorted = sortWeaponList(
        entries,
        WeaponListSortMode.rarityDesc,
        selectedWeaponId: 'eq',
      );
      expect(sorted.first.id, 'eq');
    });
  });

  group('akasha usage aggregation', () {
    test('countWeaponIdsFromBuilds and ratesFromCounts', () {
      final builds = [
        {
          'weapon': {'weaponId': 13501},
        },
        {
          'weapon': {'weaponId': '13501'},
        },
        {
          'weapon': {'weaponId': 13401},
        },
        {'weapon': null},
        {'name': 'no weapon'},
      ];
      final counts = countWeaponIdsFromBuilds(builds);
      expect(counts, {'13501': 2, '13401': 1});
      final rates = ratesFromCounts(counts);
      expect(rates['13501'], closeTo(2 / 3, 1e-9));
      expect(rates['13401'], closeTo(1 / 3, 1e-9));
    });

    test('popularity score scales with usage', () {
      final a = computeWeaponPopularityScore(usageRate: 0.5, rarity: 5);
      final b = computeWeaponPopularityScore(usageRate: 0.1, rarity: 5);
      expect(a, greaterThan(b));
      expect(a, closeTo(500.5, 0.01));
    });
  });
}
