import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_planner.dart';
import 'package:genshin_builder_mobile/domain/models/calculation_models.dart';

void main() {
  final schedule = DailyMaterialSchedule.fromJson({
    'version': 1,
    'talentSeries': [
      {
        'id': 'light',
        'name': '天光',
        'region': '稲妻',
        'days': [3, 6],
        'materialIds': ['104326', '104327', '104328'],
      },
    ],
    'weaponSeries': [
      {
        'id': 'boreal_wolf',
        'name': '凛風奔狼',
        'region': 'モンド',
        'days': [2, 5],
        'materialIds': ['114005', '114006', '114007', '114008'],
      },
    ],
  });

  final materials = <String, MasterMaterial>{
    for (final id in [
      '104326',
      '104327',
      '104328',
      '114005',
      '114006',
      '114007',
      '114008',
    ])
      id: MasterMaterial(
        id: id,
        name: '素材$id',
        category: id.startsWith('104')
            ? 'characterTalentMaterial'
            : 'weaponAscensionMaterial',
        rarity: 2,
        iconUrl: '',
      ),
  };

  group('character remaining + sort', () {
    test('owned shortage sorts above owned complete and unowned', () {
      final plan = buildDailyMaterialsPlan(
        schedule: schedule,
        weekday: DateTime.wednesday,
        materials: materials,
        characters: [
          const CharacterTalentCatalogEntry(
            character: MasterCharacter(
              id: 'unowned',
              name: '未所持キャラ',
              element: 'electro',
              weaponType: 'sword',
              rarity: 5,
              region: '稲妻',
              iconUrl: '',
            ),
            talentMaterialIds: {'104328'},
          ),
          const CharacterTalentCatalogEntry(
            character: MasterCharacter(
              id: 'complete',
              name: '八重神子',
              element: 'electro',
              weaponType: 'catalyst',
              rarity: 5,
              region: '稲妻',
              iconUrl: '',
            ),
            talentMaterialIds: {'104328'},
            isOwned: true,
            progress: UserProgress(
              id: 'p2',
              userId: 'u',
              characterId: 'complete',
              talentNormal: 10,
              talentSkill: 10,
              talentBurst: 10,
            ),
            talents: {
              'skill_0': [
                TalentLevelUpgrade(
                  level: 2,
                  coinCost: 0,
                  costItems: {'104328': 3},
                ),
              ],
              'skill_1': [],
              'skill_2': [],
            },
          ),
          const CharacterTalentCatalogEntry(
            character: MasterCharacter(
              id: 'need',
              name: '雷電将軍',
              element: 'electro',
              weaponType: 'polearm',
              rarity: 5,
              region: '稲妻',
              iconUrl: '',
            ),
            talentMaterialIds: {'104328'},
            isOwned: true,
            progress: UserProgress(
              id: 'p1',
              userId: 'u',
              characterId: 'need',
              talentNormal: 1,
              talentSkill: 10,
              talentBurst: 10,
            ),
            talents: {
              'skill_0': [
                TalentLevelUpgrade(
                  level: 2,
                  coinCost: 0,
                  costItems: {'104328': 12},
                ),
              ],
              'skill_1': [],
              'skill_2': [],
            },
          ),
        ],
        weapons: const [],
      );

      final consumers = plan.talentCards.single.consumers;
      expect(consumers.map((c) => c.name).toList(), [
        '雷電将軍',
        '八重神子',
        '未所持キャラ',
      ]);
      expect(consumers[0].remainingStatus, DailyRemainingStatus.needed);
      expect(consumers[0].remainingCount, 12);
      expect(consumers[0].remainingByMaterialId, {'104328': 12});
      expect(consumers[0].nextStageByMaterialId, {'104328': 12});
      expect(plan.talentCards.single.remainingByMaterialId, {'104328': 12});
      expect(plan.talentCards.single.nextStageByMaterialId, {'104328': 12});
      expect(consumers[1].remainingStatus, DailyRemainingStatus.complete);
      expect(consumers[2].remainingStatus, DailyRemainingStatus.unknown);
    });
  });

  group('weapon equipped characters', () {
    test('shows equipped characters and groups by type', () {
      final plan = buildDailyMaterialsPlan(
        schedule: schedule,
        weekday: DateTime.tuesday,
        materials: materials,
        characters: const [],
        weapons: [
          const WeaponAscensionCatalogEntry(
            weapon: MasterWeapon(
              id: 'w1',
              name: '草薙の稲光',
              weaponType: 'polearm',
              rarity: 5,
              iconUrl: '',
            ),
            ascensionMaterialIds: {'114005'},
            weaponLevel: 80,
            weaponRefinement: 1,
            promotes: [
              PromoteStage(
                promoteLevel: 5,
                unlockMaxLevel: 90,
                costItems: {'114008': 5},
                coinCost: 0,
              ),
            ],
            equippedCharacters: [
              DailyEquippedCharacter(
                id: '10000052',
                name: '雷電将軍',
                iconUrl: 'raiden.png',
              ),
            ],
            isOwned: true,
          ),
          const WeaponAscensionCatalogEntry(
            weapon: MasterWeapon(
              id: 'w2',
              name: '風鷹剣',
              weaponType: 'sword',
              rarity: 5,
              iconUrl: '',
            ),
            ascensionMaterialIds: {'114008'},
          ),
        ],
      );

      final card = plan.weaponCards.single;
      expect(card.consumerGroups.map((g) => g.key), ['sword', 'polearm']);
      final polearm = card.consumerGroups
          .firstWhere((g) => g.key == 'polearm')
          .consumers
          .single;
      expect(polearm.equippedCharacters.single.name, '雷電将軍');
      expect(polearm.isOwned, isTrue);
      expect(polearm.isEquipped, isTrue);
      // Lv 既知なら不足 or 完成のいずれか（unknown ではない）
      expect(
        polearm.remainingStatus,
        isNot(DailyRemainingStatus.unknown),
      );
    });
  });

  group('compare helpers', () {
    test('compareDailyCharacterConsumers prefers owned shortage', () {
      const a = DailyMaterialConsumer(
        id: 'a',
        name: 'A',
        isOwned: true,
        remainingStatus: DailyRemainingStatus.needed,
        remainingCount: 5,
      );
      const b = DailyMaterialConsumer(
        id: 'b',
        name: 'B',
        isOwned: true,
        remainingStatus: DailyRemainingStatus.complete,
      );
      expect(compareDailyCharacterConsumers(a, b), lessThan(0));
    });
  });
}
