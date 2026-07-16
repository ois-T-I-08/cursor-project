import 'package:genshin_builder_mobile/domain/artifact_completion.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';
import 'package:genshin_builder_mobile/domain/artifacts/artifact_set_overview.dart';
import 'package:genshin_builder_mobile/domain/models/amber_detail_models.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('artifact_completion', () {
    test('empty piece is 0%', () {
      final pct = calcArtifactPieceCompletionPercent(
        createEmptyArtifactPiece(),
        scoreType: ArtifactScoreType.atk,
      );
      expect(pct, 0);
    });

    test('equipped maxed piece approaches 100%', () {
      const piece = ArtifactPiece(
        setName: '絶縁の旗印',
        mainStat: '攻撃力%',
        level: 20,
        substats: [
          ArtifactSubstat(stat: '会心率', value: 10),
          ArtifactSubstat(stat: '会心ダメージ', value: 20),
          ArtifactSubstat(stat: '攻撃力%', value: 5),
          ArtifactSubstat(stat: '元素チャージ効率', value: 5),
        ],
      );
      final pct = calcArtifactPieceCompletionPercent(
        piece,
        scoreType: ArtifactScoreType.atk,
      );
      expect(pct, greaterThan(80));
      expect(pct, lessThanOrEqualTo(100));
    });

    test('overall averages five slots', () {
      final state = createEmptyArtifactState();
      state[ArtifactSlotKey.flower] = const ArtifactPiece(
        setName: '絶縁の旗印',
        mainStat: 'HP',
        level: 20,
      );
      final report = calcArtifactCompletionReport(
        state,
        scoreType: ArtifactScoreType.atk,
      );
      expect(report.bySlot[ArtifactSlotKey.flower], greaterThan(0));
      expect(report.overallPercent, lessThan(report.bySlot[ArtifactSlotKey.flower]!));
    });
  });

  group('artifact_set_overview', () {
    test('only lists characters with 2+ pieces of the set', () {
      const raiden = MasterCharacter(
        id: '10000052',
        name: '雷電将軍',
        element: '雷',
        rarity: 5,
        weaponType: '長柄武器',
        region: '稲妻',
        iconUrl: '',
        scoreType: 'recharge',
      );
      const xiangling = MasterCharacter(
        id: '10000023',
        name: '香菱',
        element: '炎',
        rarity: 4,
        weaponType: '長柄武器',
        region: '璃月',
        iconUrl: '',
        scoreType: 'atk',
      );
      const zhongli = MasterCharacter(
        id: '10000030',
        name: '鍾離',
        element: '岩',
        rarity: 5,
        weaponType: '長柄武器',
        region: '璃月',
        iconUrl: '',
        scoreType: 'hp',
      );

      const emblem = ArtifactSetDetail(
        id: '15020',
        name: '絶縁の旗印',
        iconUrl: 'emblem.png',
        effects: [],
        route: 'Emblem of Severed Fate',
      );
      const glad = ArtifactSetDetail(
        id: '15001',
        name: '剣闘士のフィナーレ',
        iconUrl: 'glad.png',
        effects: [],
        route: "Gladiator's Finale",
      );
      final catalog = ArtifactSetCatalog.fromSets([emblem, glad]);

      final progress = [
        UserProgress(
          id: '1',
          userId: 'u',
          characterId: raiden.id,
          artifactsJson: encodeArtifactState({
            ArtifactSlotKey.flower: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.plume: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.sands: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.goblet: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.circlet: const ArtifactPiece(setName: '絶縁の旗印'),
          }),
          artifactCompleted: true,
        ),
        UserProgress(
          id: '2',
          userId: 'u',
          characterId: xiangling.id,
          artifactsJson: encodeArtifactState({
            ArtifactSlotKey.flower: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.plume: createEmptyArtifactPiece(),
            ArtifactSlotKey.sands: createEmptyArtifactPiece(),
            ArtifactSlotKey.goblet: createEmptyArtifactPiece(),
            ArtifactSlotKey.circlet: createEmptyArtifactPiece(),
          }),
        ),
        UserProgress(
          id: '3',
          userId: 'u',
          characterId: zhongli.id,
          artifactsJson: encodeArtifactState({
            ArtifactSlotKey.flower: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.plume: const ArtifactPiece(setName: '絶縁の旗印'),
            ArtifactSlotKey.sands: const ArtifactPiece(setName: '剣闘士のフィナーレ'),
            ArtifactSlotKey.goblet: const ArtifactPiece(setName: '剣闘士のフィナーレ'),
            ArtifactSlotKey.circlet: createEmptyArtifactPiece(),
          }),
        ),
      ];

      final grouped = groupEquippedBySetId(
        inputs: artifactEquipInputsFromProgress(progress),
        charactersById: {
          raiden.id: raiden,
          xiangling.id: xiangling,
          zhongli.id: zhongli,
        },
        ownedCharacterIds: {xiangling.id, zhongli.id},
        catalog: catalog,
      );

      // 1部位のみの香菱は除外、4セット雷電と2セット鍾離のみ
      expect(grouped['15020']!.length, 2);
      expect(grouped['15020']!.any((e) => e.character.id == xiangling.id), isFalse);

      final four = grouped['15020']!
          .firstWhere((e) => e.character.id == raiden.id);
      expect(four.isFourSet, isTrue);
      expect(four.companionSets, isEmpty);
      expect(four.artifactCompleted, isTrue);

      final two = grouped['15020']!
          .firstWhere((e) => e.character.id == zhongli.id);
      expect(two.isTwoSet, isTrue);
      expect(two.companionSets.length, 2);
      expect(two.companionSets.map((s) => s.setName), contains('剣闘士のフィナーレ'));
      expect(
        two.companionSets.firstWhere((s) => s.setName == '剣闘士のフィナーレ').iconUrl,
        'glad.png',
      );
    });

    test('resolves set by icon id even when setName language differs', () {
      const varesa = MasterCharacter(
        id: '10000111',
        name: 'ヴァレサ',
        element: '雷',
        rarity: 5,
        weaponType: '法器',
        region: 'ナタ',
        iconUrl: '',
      );
      const scroll = ArtifactSetDetail(
        id: '15037',
        name: '灰燼の都に立つ英雄の絵巻',
        iconUrl:
            'https://gi.yatta.moe/assets/UI/reliquary/UI_RelicIcon_15037_4.png',
        effects: [],
        route: 'Scroll of the Hero of Cinder City',
      );
      final catalog = ArtifactSetCatalog.fromSets([scroll]);

      final progress = [
        UserProgress(
          id: '1',
          userId: 'u',
          characterId: varesa.id,
          artifactsJson: encodeArtifactState({
            // HoYoLAB 等が別言語名でも icon で解決できる
            ArtifactSlotKey.flower: const ArtifactPiece(
              setName: 'Scroll of the Hero of Cinder City',
              iconUrl:
                  'https://enka.network/ui/UI_RelicIcon_15037_4.png',
            ),
            ArtifactSlotKey.plume: const ArtifactPiece(
              setName: '未知の名前',
              iconUrl: 'UI_RelicIcon_15037_2.png',
            ),
            ArtifactSlotKey.sands: const ArtifactPiece(
              setName: '',
              iconUrl: 'UI_RelicIcon_15037_1.png',
            ),
            ArtifactSlotKey.goblet: const ArtifactPiece(
              setName: '',
              iconUrl: 'UI_RelicIcon_15037_3.png',
            ),
            ArtifactSlotKey.circlet: createEmptyArtifactPiece(),
          }),
        ),
      ];

      final grouped = groupEquippedBySetId(
        inputs: artifactEquipInputsFromProgress(progress),
        charactersById: {varesa.id: varesa},
        ownedCharacterIds: {varesa.id},
        catalog: catalog,
      );

      expect(grouped['15037']!.single.character.name, 'ヴァレサ');
      expect(grouped['15037']!.single.isFourSet, isTrue);
    });

    test('resolves set via aliases when names differ', () {
      const furina = MasterCharacter(
        id: '10000089',
        name: 'フリーナ',
        element: '水',
        rarity: 5,
        weaponType: '片手剣',
        region: 'フォンテーヌ',
        iconUrl: '',
      );
      const troupe = ArtifactSetDetail(
        id: '15034',
        name: '黄金の劇団',
        iconUrl: null,
        effects: [],
        route: 'Golden Troupe',
      );
      final catalog = ArtifactSetCatalog.fromSets(
        [troupe],
        aliases: const {'黄金劇団': '黄金の劇団'},
      );

      final grouped = groupEquippedBySetId(
        inputs: [
          ArtifactEquipInput(
            characterId: furina.id,
            pieces: const [
              ArtifactPiece(setName: '黄金劇団'),
              ArtifactPiece(setName: '黄金劇団'),
              ArtifactPiece(setName: '黄金劇団'),
              ArtifactPiece(setName: '黄金劇団'),
            ],
          ),
        ],
        charactersById: {furina.id: furina},
        ownedCharacterIds: {furina.id},
        catalog: catalog,
      );

      expect(grouped['15034']!.single.character.name, 'フリーナ');
    });

    test('builds overviews with recommendations', () {
      const set = ArtifactSetDetail(
        id: '1',
        name: '絶縁の旗印',
        iconUrl: null,
        effects: ['元素チャージ効率+20%', '元素爆発ダメージアップ'],
        route: 'Emblem of Severed Fate',
      );
      const raiden = MasterCharacter(
        id: '10000052',
        name: '雷電将軍',
        element: '雷',
        rarity: 5,
        weaponType: '長柄武器',
        region: '稲妻',
        iconUrl: '',
        scoreType: 'recharge',
      );

      final list = buildArtifactSetOverviews(
        sets: [set],
        equippedBySetId: const {},
        charactersById: {raiden.id: raiden},
        charactersByName: {raiden.name: raiden},
        configRecommendationsBySetName: {
          '絶縁の旗印': ['雷電将軍'],
        },
      );

      expect(list.single.twoPieceEffect, contains('元素チャージ'));
      expect(list.single.recommendedCharacters.single.character.name, '雷電将軍');
    });

    test('prefers akasha hits over config', () {
      const set = ArtifactSetDetail(
        id: '15020',
        name: '絶縁の旗印',
        iconUrl: null,
        effects: [],
        route: 'Emblem of Severed Fate',
      );
      const raiden = MasterCharacter(
        id: '10000052',
        name: '雷電将軍',
        element: '雷',
        rarity: 5,
        weaponType: '長柄武器',
        region: '稲妻',
        iconUrl: '',
        scoreType: 'recharge',
      );
      const xiangling = MasterCharacter(
        id: '10000023',
        name: '香菱',
        element: '炎',
        rarity: 4,
        weaponType: '長柄武器',
        region: '璃月',
        iconUrl: '',
        scoreType: 'atk',
      );

      final list = buildArtifactSetOverviews(
        sets: [set],
        equippedBySetId: const {},
        charactersById: {raiden.id: raiden, xiangling.id: xiangling},
        charactersByName: {
          raiden.name: raiden,
          xiangling.name: xiangling,
        },
        akashaByEnglishSet: {
          'Emblem of Severed Fate': [
            const ArtifactSetRecommendationHit(
              characterId: '10000052',
              usageRate: 0.9,
              source: 'akasha',
            ),
          ],
        },
        configRecommendationsBySetName: {
          '絶縁の旗印': ['香菱'],
        },
      );

      expect(list.single.recommendedCharacters.first.character.id, raiden.id);
      expect(list.single.recommendedCharacters.first.isFromAkasha, isTrue);
      expect(list.single.recommendedCharacters.last.character.id, xiangling.id);
    });
  });
}
