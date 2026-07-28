import '../../domain/level_config.dart';
import '../../domain/models/calculation_models.dart';

/// `level_exp_table.json` / 組み込みマップから [LevelExpSegment] を構築する。
class LevelExpTableBuilder {
  LevelExpTableBuilder._();

  /// [weapon_exp.dart] と同じ武器 EXP 表（asset 未読時のフォールバック用）
  static const defaultWeaponExpByRarity = <int, Map<String, int>>{
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

  static List<LevelExpSegment> buildFromJson(Map<String, dynamic> json) {
    final characterRaw = json['characterExp'] as Map<String, dynamic>? ?? {};
    final characterExp = <String, int>{
      for (final e in characterRaw.entries) e.key: (e.value as num).toInt(),
    };

    final weaponRaw = json['weaponExpByRarity'] as Map<String, dynamic>? ?? {};
    final weaponExpByRarity = <int, Map<String, int>>{};
    for (final e in weaponRaw.entries) {
      final rarity = int.tryParse(e.key) ?? 0;
      final table = e.value as Map<String, dynamic>? ?? {};
      weaponExpByRarity[rarity] = {
        for (final te in table.entries) te.key: (te.value as num).toInt(),
      };
    }

    final marksRaw = json['levelMarks'] as List<dynamic>?;
    final marks =
        marksRaw == null
            ? levelMarks
            : marksRaw.map((e) => (e as num).toInt()).toList(growable: false);

    return buildFromMaps(
      characterExp: characterExp,
      weaponExpByRarity: weaponExpByRarity,
      marks: marks,
    );
  }

  static List<LevelExpSegment> buildFromMaps({
    required Map<String, int> characterExp,
    required Map<int, Map<String, int>> weaponExpByRarity,
    List<int> marks = levelMarks,
  }) {
    final segments = <LevelExpSegment>[];
    for (var i = 0; i < marks.length - 1; i++) {
      final from = marks[i];
      final to = marks[i + 1];
      final key = '$from-$to';
      final charExp = characterExp[key] ?? 0;
      segments.add(
        LevelExpSegment(
          id: 'character-0-$from-$to',
          targetType: 'character',
          rarity: 0,
          fromLevel: from,
          toLevel: to,
          expRequired: charExp,
          moraRequired: (charExp / 10).round(),
        ),
      );

      for (final rarity in [3, 4, 5]) {
        final exp = weaponExpByRarity[rarity]?[key] ?? 0;
        segments.add(
          LevelExpSegment(
            id: 'weapon-$rarity-$from-$to',
            targetType: 'weapon',
            rarity: rarity,
            fromLevel: from,
            toLevel: to,
            expRequired: exp,
            moraRequired: (exp / 10).round(),
          ),
        );
      }
    }
    return segments;
  }
}
