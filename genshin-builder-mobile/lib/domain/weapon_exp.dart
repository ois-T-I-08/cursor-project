import 'level_config.dart';

const weaponEnhancementOres = [
  (id: '104013', name: '仕上げ用魔鉱', exp: 10000),
  (id: '104012', name: '仕上げ用良鉱', exp: 2000),
  (id: '104011', name: '仕上げ用雑鉱', exp: 400),
];

const _weaponExpByRarity = <int, Map<String, int>>{
  3: {
    '1-20': 53475,
    '20-30': 127978,
    '30-40': 145247,
    '40-50': 275350,
    '50-60': 408650,
    '60-70': 572725,
    '70-80': 772825,
    '80-90': 1638650,
  },
  4: {
    '1-20': 81000,
    '20-30': 194512,
    '30-40': 220613,
    '40-50': 418725,
    '50-60': 618400,
    '60-70': 866675,
    '70-80': 1168350,
    '80-90': 2476475,
  },
  5: {
    '1-20': 121550,
    '20-30': 291591,
    '30-40': 331209,
    '40-50': 628150,
    '50-60': 927675,
    '60-70': 1299125,
    '70-80': 1750375,
    '80-90': 3714775,
  },
};

Map<String, int> _resolveRarityTable(int rarity) {
  if (rarity >= 5) return _weaponExpByRarity[5]!;
  if (rarity == 4) return _weaponExpByRarity[4]!;
  return _weaponExpByRarity[3]!;
}

int _snapMark(int level) {
  var closest = levelMarksList.first;
  var minDiff = (level - closest).abs();
  for (final mark in levelMarksList) {
    final diff = (level - mark).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = mark;
    }
  }
  return closest;
}

/// 目盛り間の必要武器EXPを合算
int getWeaponExpBetweenMarks(int from, int to, int rarity) {
  final table = _resolveRarityTable(rarity);
  final fromMark = _snapMark(from);
  final toMark = _snapMark(to);
  if (toMark <= fromMark) return 0;

  var total = 0;
  final startIdx = levelMarksList.indexOf(fromMark);
  for (
    var i = startIdx < 0 ? 0 : startIdx;
    i < levelMarksList.length - 1;
    i++
  ) {
    final a = levelMarksList[i];
    final b = levelMarksList[i + 1];
    if (b <= fromMark) continue;
    if (a >= toMark) break;
    total += table['$a-$b'] ?? 0;
    if (b >= toMark) break;
  }
  return total;
}

int getWeaponLevelUpMora(int expTotal) => (expTotal / 10).round();

List<({String materialId, String name, int count})> suggestWeaponOres(
  int totalExp,
) {
  if (totalExp <= 0) return [];
  var remaining = totalExp;
  final result = <({String materialId, String name, int count})>[];

  for (final ore in weaponEnhancementOres) {
    final count = remaining ~/ ore.exp;
    if (count > 0) {
      result.add((materialId: ore.id, name: ore.name, count: count));
      remaining -= count * ore.exp;
    }
  }
  if (remaining > 0) {
    final fine = weaponEnhancementOres[2];
    final extra = (remaining / fine.exp).ceil();
    final idx = result.indexWhere((r) => r.materialId == fine.id);
    if (idx >= 0) {
      final prev = result[idx];
      result[idx] = (
        materialId: prev.materialId,
        name: prev.name,
        count: prev.count + extra,
      );
    } else {
      result.add((materialId: fine.id, name: fine.name, count: extra));
    }
  }
  return result;
}

List<String> parseWeaponEnhancementOreIds(Map<String, dynamic>? items) {
  if (items == null) {
    return weaponEnhancementOres.map((o) => o.id).toList();
  }
  return weaponEnhancementOres
      .where((o) => items.containsKey(o.id))
      .map((o) => o.id)
      .toList();
}
