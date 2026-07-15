import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/planning/character_farm_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/resin_farm_cost_table.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';

ResinFarmCostTable _table() => ResinFarmCostTable.fromJson({
      'version': 2,
      'meta': {
        'naturalResinPerDay': 180,
        'condensedResinValue': 40,
        'synthesisRatio': 3,
        'weekdayLabels': ['月', '火', '水', '木', '金', '土', '日'],
      },
      'kinds': {
        'talentDomain': {
          'resinPerRun': 20,
          'assumedDropsPerRun': 2.2,
          'contentLabel': '熟知秘境',
        },
        'weaponDomain': {
          'resinPerRun': 20,
          'assumedDropsPerRun': 2.2,
          'contentLabel': '煉武秘境',
        },
        'artifactDomain': {
          'resinPerRun': 20,
          'assumedDropsPerRun': 1,
          'contentLabel': '聖遺物秘境',
        },
        'weeklyBoss': {
          'resinPerRun': 30,
          'assumedDropsPerRun': 1,
          'assumedDropsPerRunMin': 1,
          'assumedDropsPerRunMax': 2,
          'challengesPerWeek': 3,
          'contentLabel': '週ボス',
        },
        'worldBoss': {
          'resinPerRun': 40,
          'assumedDropsPerRun': 2,
          'assumedDropsPerRunMin': 1.5,
          'assumedDropsPerRunMax': 2.5,
          'contentLabel': 'フィールドボス',
        },
        'leyLineExp': {
          'resinPerRun': 20,
          'assumedHeroWitEquivalentPerRun': 2.5,
          'contentLabel': '地脈の花（経験値）',
        },
        'leyLineMora': {
          'resinPerRun': 20,
          'assumedMoraPerRun': 60000,
          'contentLabel': 'モラ地脈',
        },
      },
      'zeroResinCategories': [
        'localSpecialtyLiyue',
        'characterandWeaponEnhancementMaterial',
      ],
    });

DailyMaterialSeries _prosperity() => const DailyMaterialSeries(
      id: 'prosperity',
      name: '繁栄',
      region: '璃月',
      kind: DailyMaterialKind.talentBook,
      days: [1, 4],
      materialIds: ['104311', '104312', '104313'], // 教え・導き・哲学
    );

Map<String, DailyMaterialSeries> _index(DailyMaterialSeries s) => {
      for (final id in s.materialIds) id: s,
    };

final _now = DateTime.utc(2026, 1, 1);

void main() {
  final table = _table();

  group('buildCharacterFarmPlan', () {
    test('経験値本の地脈周回数（切り上げ・EXP換算）', () {
      // 大英雄 180冊 = 180 * 20000 exp / 20000 = 180 hero equiv
      // ceil(180 / 2.5) = 72 runs * 20 = 1440
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 180},
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final exp = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.runsExpected, 72);
      expect(exp.resinTotal, 1440);
      expect(exp.materials.single.shortage, 180);
    });

    test('経験値本の混合レアを共通EXPへ換算', () {
      // 流浪者 10 * 1000 + 冒険家 2 * 5000 = 20000 = 1 hero
      // ceil(1 / 2.5) = 1 run
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104001': 10, '104002': 2},
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final exp = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.runsExpected, 1);
      expect(exp.resinTotal, 20);
    });

    test('モラ地脈の周回数', () {
      // ceil(720000/60000)=12 * 20 = 240
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            moraCost: 720000,
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final mora = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineMora);
      expect(mora.runsExpected, 12);
      expect(mora.resinTotal, 240);
    });

    test('天賦秘境の周回数と開放曜日', () {
      final series = _prosperity();
      // Need 14 philosophy (weight 9) = 126 base units
      // dropsInBase = 2.2 * 9 = 19.8 → ceil(126/19.8)=7 → 140 resin
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'talentNormal',
            materialsCost: {'104313': 14},
          ),
        ],
        table: table,
        materialIndex: _index(series),
        nowUtc: _now,
      );
      final talent =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.talentDomain);
      expect(talent.runsExpected, 7);
      expect(talent.resinTotal, 140);
      expect(talent.openWeekdayLabels, containsAll(['月', '木', '日']));
    });

    test('素材合成を考慮した計算', () {
      final series = _prosperity();
      // 教え 3 + 導き 1 = 3*1 + 1*3 = 6 base; need 哲学 1 = 9
      // owned: 教え 3 → ownedUnits 3; neededUnits 9; shortageUnits 6
      // ceil(6 / 19.8) = 1
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'talentNormal',
            materialsCost: {'104313': 1},
            ownedMaterials: {'104311': 3},
            inventoryStatus: InventoryStatus.ownedInsufficient,
          ),
        ],
        table: table,
        materialIndex: _index(series),
        nowUtc: _now,
      );
      final talent =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.talentDomain);
      expect(talent.runsExpected, 1);
      expect(talent.resinTotal, 20);
    });

    test('所持数差し引き', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 46},
            ownedMaterials: {'104003': 18},
            inventoryStatus: InventoryStatus.ownedInsufficient,
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final exp = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      final line = exp.materials.single;
      expect(line.needed, 46);
      expect(line.owned, 18);
      expect(line.shortage, 28);
      // ceil(28/2.5)=12 * 20 = 240
      expect(exp.runsExpected, 12);
      expect(exp.resinTotal, 240);
    });

    test('不足0の場合は樹脂0でセクションなし', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 10},
            ownedMaterials: {'104003': 10},
            inventoryStatus: InventoryStatus.ownedSufficient,
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      expect(plan.sections, isEmpty);
      expect(plan.totalResin, 0);
      expect(plan.naturalRegenDays, 0);
      expect(plan.condensedResinCount, 0);
    });

    test('端数切り上げ（モラ）', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            moraCost: 60001,
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final mora = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineMora);
      expect(mora.runsExpected, 2);
      expect(mora.resinTotal, 40);
    });

    test('ボスドロップ幅は推定モード', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'ascension',
            materialsCost: {'boss_mat': 16},
          ),
        ],
        table: table,
        materialCategories: {
          'boss_mat': 'characterLevelUpMaterial',
        },
        materialNames: {'boss_mat': 'ボス素材'},
        nowUtc: _now,
      );
      final boss =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.worldBoss);
      expect(boss.estimateMode, FarmEstimateMode.range);
      // expected: ceil(16/2)=8; min drops 2.5 → ceil(16/2.5)=7; max runs ceil(16/1.5)=11
      expect(boss.runsExpected, 8);
      expect(boss.runsMin, 7);
      expect(boss.runsMax, 11);
      expect(boss.resinTotal, 320);
      expect(boss.resinMin, 280);
      expect(boss.resinMax, 440);
    });

    test('週ボスの推定（週数・樹脂幅）', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'talentNormal',
            materialsCost: {'weekly_mat': 4},
          ),
        ],
        table: table,
        materialIndex: {
          'weekly_mat': const DailyMaterialSeries(
            id: 'weekly',
            name: '週ボス',
            region: '',
            kind: DailyMaterialKind.weeklyBoss,
            days: [],
            materialIds: ['weekly_mat'],
          ),
        },
        materialNames: {'weekly_mat': '週ボス素材'},
        nowUtc: _now,
      );
      final weekly =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.weeklyBoss);
      expect(weekly.estimateMode, FarmEstimateMode.range);
      // ceil(4/1)=4 max runs, ceil(4/2)=2 min runs
      expect(weekly.runsMin, 2);
      expect(weekly.runsMax, 4);
      expect(weekly.runsExpected, 4);
      expect(weekly.resinMin, 60);
      expect(weekly.resinMax, 120);
      // challengesPerWeek=3 → weeks ceil(2/3)=1 .. ceil(4/3)=2
      expect(weekly.weeksMin, 1);
      expect(weekly.weeksMax, 2);
    });

    test('樹脂不要素材は合計へ含めない', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'ascension',
            materialsCost: {
              'qingxin': 42,
              '104003': 5,
            },
            moraCost: 60000,
          ),
        ],
        table: table,
        materialCategories: {
          'qingxin': 'localSpecialtyLiyue',
        },
        materialNames: {'qingxin': '清心'},
        nowUtc: _now,
      );
      expect(plan.zeroResinMaterials, hasLength(1));
      expect(plan.zeroResinMaterials.single.name, '清心');
      expect(plan.zeroResinMaterials.single.shortage, 42);
      final resinKinds = plan.sections.map((s) => s.kind).toSet();
      expect(resinKinds, isNot(contains(ResinFarmKind.zeroResin)));
      // only exp + mora
      expect(plan.totalResin, plan.sections.fold<int>(0, (s, x) => s + x.resinTotal));
      expect(
        plan.sections.every((s) => s.kind != ResinFarmKind.zeroResin),
        isTrue,
      );
    });

    test('複数キャラ集約時の所持重複防止', () {
      final opts = [
        const UpgradeOption(
          optionId: 'a',
          characterId: 'c1',
          optionType: 'level',
          expItemCost: {'104003': 20},
          ownedMaterials: {'104003': 10},
          inventoryStatus: InventoryStatus.ownedInsufficient,
        ),
        const UpgradeOption(
          optionId: 'b',
          characterId: 'c2',
          optionType: 'level',
          expItemCost: {'104003': 15},
          ownedMaterials: {'104003': 10},
          inventoryStatus: InventoryStatus.ownedInsufficient,
        ),
      ];
      final plan = mergeCharacterFarmPlans(
        allOptions: opts,
        table: table,
        nowUtc: _now,
      );
      final exp = plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      final line = exp.materials.single;
      expect(line.needed, 35);
      expect(line.owned, 10); // max, not 20
      expect(line.shortage, 25);
    });

    test('樹脂合計と自然回復・濃縮換算の整合性', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            moraCost: 720000,
            expItemCost: {'104003': 5},
          ),
        ],
        table: table,
        nowUtc: _now,
      );
      final sum = plan.sections.fold<int>(0, (s, x) => s + x.resinTotal);
      expect(plan.totalResin, sum);
      expect(plan.naturalRegenDays, (sum / 180).ceil());
      expect(plan.condensedResinCount, (sum / 40).ceil());
    });
  });
}
