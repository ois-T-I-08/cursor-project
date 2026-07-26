import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/planning/resin_farm_cost_table.dart';
import 'package:genshin_builder_mobile/domain/planning/resin_farm_estimate.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';
import 'package:genshin_builder_mobile/data/config/config_validators.dart';

ResinFarmCostTable _table() => ResinFarmCostTable.fromJson({
      'version': 1,
      'kinds': {
        'talentDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2},
        'weaponDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2},
        'artifactDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
        'weeklyBoss': {'resinPerRun': 30, 'assumedDropsPerRun': 1},
        'worldBoss': {'resinPerRun': 40, 'assumedDropsPerRun': 2},
        'leyLineExp': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
        'leyLineMora': {'resinPerRun': 20, 'assumedMoraPerRun': 60000},
      },
      'zeroResinCategories': ['localSpecialtyMondstadt'],
    });

void main() {
  group('validateResinFarmCostsJson', () {
    test('accepts valid table', () {
      expect(() => validateResinFarmCostsJson({
            'version': 1,
            'kinds': {
              'talentDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
              'weaponDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
              'artifactDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
              'weeklyBoss': {'resinPerRun': 30, 'assumedDropsPerRun': 1},
              'worldBoss': {'resinPerRun': 40, 'assumedDropsPerRun': 2},
              'leyLineExp': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
              'leyLineMora': {'resinPerRun': 20, 'assumedMoraPerRun': 60000},
            },
          }), returnsNormally);
    });

    test('rejects missing kind', () {
      expect(
        () => validateResinFarmCostsJson({'version': 1, 'kinds': {}}),
        throwsFormatException,
      );
    });
  });

  group('classifyResinFarmKind', () {
    final table = _table();

    test('uses schedule index for talent books', () {
      final kind = classifyResinFarmKind(
        materialId: '104301',
        table: table,
        materialIndex: {
          '104301': const DailyMaterialSeries(
            id: 'freedom',
            name: '自由',
            region: 'モンド',
            kind: DailyMaterialKind.talentBook,
            days: [1, 4],
            materialIds: ['104301'],
          ),
        },
      );
      expect(kind, ResinFarmKind.talentDomain);
    });

    test('exp books are ley line', () {
      expect(
        classifyResinFarmKind(materialId: '104003', table: table),
        ResinFarmKind.leyLineExp,
      );
    });

    test('zero resin category', () {
      expect(
        classifyResinFarmKind(
          materialId: 'x',
          table: table,
          materialCategories: {'x': 'localSpecialtyMondstadt'},
        ),
        ResinFarmKind.zeroResin,
      );
    });

    test('unknown is unknown', () {
      expect(
        classifyResinFarmKind(materialId: 'unknown_mat', table: table),
        ResinFarmKind.unknown,
      );
    });
  });

  group('estimateResinCostForUpgradeOption', () {
    final table = _table();

    test('ceils drops for talent domain', () {
      const option = UpgradeOption(
        optionId: 'o1',
        characterId: 'c1',
        optionType: 'talentNormal',
        materialsCost: {'104301': 5},
      );
      final resin = estimateResinCostForUpgradeOption(
        option: option,
        table: table,
        materialIndex: {
          '104301': const DailyMaterialSeries(
            id: 'freedom',
            name: '自由',
            region: 'モンド',
            kind: DailyMaterialKind.talentBook,
            days: [1, 4],
            materialIds: ['104301'],
          ),
        },
      );
      // ceil(5/2)=3 runs * 20 = 60
      expect(resin, 60);
    });

    test('mora uses ley line', () {
      const option = UpgradeOption(
        optionId: 'o1',
        characterId: 'c1',
        optionType: 'level',
        moraCost: 60001,
      );
      expect(
        estimateResinCostForUpgradeOption(option: option, table: table),
        40,
      );
    });

    test('unknown materials contribute 0', () {
      const option = UpgradeOption(
        optionId: 'o1',
        characterId: 'c1',
        optionType: 'level',
        materialsCost: {'zzz': 99},
      );
      expect(
        estimateResinCostForUpgradeOption(option: option, table: table),
        0,
      );
    });

    test('uses remaining when inventory set', () {
      const option = UpgradeOption(
        optionId: 'o1',
        characterId: 'c1',
        optionType: 'talentNormal',
        materialsCost: {'104301': 10},
        remainingMaterials: {'104301': 3},
        inventoryStatus: InventoryStatus.ownedInsufficient,
      );
      final resin = estimateResinCostForUpgradeOption(
        option: option,
        table: table,
        materialIndex: {
          '104301': const DailyMaterialSeries(
            id: 'freedom',
            name: '自由',
            region: 'モンド',
            kind: DailyMaterialKind.talentBook,
            days: [1, 4],
            materialIds: ['104301'],
          ),
        },
      );
      // ceil(3/2)=2 * 20 = 40
      expect(resin, 40);
    });
    test('exp books convert via hero-wit equivalent', () {
      final v2 = ResinFarmCostTable.fromJson({
        'version': 2,
        'kinds': {
          'talentDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2},
          'weaponDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2},
          'artifactDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
          'weeklyBoss': {'resinPerRun': 30, 'assumedDropsPerRun': 1},
          'worldBoss': {'resinPerRun': 40, 'assumedDropsPerRun': 2},
          'leyLineExp': {
            'resinPerRun': 20,
            'assumedHeroWitEquivalentPerRun': 2.5,
          },
          'leyLineMora': {'resinPerRun': 20, 'assumedMoraPerRun': 60000},
        },
      });
      const option = UpgradeOption(
        optionId: 'o1',
        characterId: 'c1',
        optionType: 'level',
        expItemCost: {'104003': 5},
      );
      // ceil(5/2.5)=2 * 20 = 40
      expect(
        estimateResinCostForUpgradeOption(option: option, table: v2),
        40,
      );
    });

    test('accepts leyLineExp with hero-wit only', () {
      expect(
        () => validateResinFarmCostsJson({
          'version': 2,
          'kinds': {
            'talentDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
            'weaponDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
            'artifactDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
            'weeklyBoss': {'resinPerRun': 30, 'assumedDropsPerRun': 1},
            'worldBoss': {'resinPerRun': 40, 'assumedDropsPerRun': 2},
            'leyLineExp': {
              'resinPerRun': 20,
              'assumedHeroWitEquivalentPerRun': 2.5,
            },
            'leyLineMora': {'resinPerRun': 20, 'assumedMoraPerRun': 60000},
          },
        }),
        returnsNormally,
      );
    });
  });
}
