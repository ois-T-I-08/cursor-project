import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/artifacts/character_recommended_artifact_sets.dart';
import 'package:genshin_builder_mobile/domain/models/amber_detail_models.dart';

void main() {
  const emblem = ArtifactSetDetail(
    id: '15020',
    name: '絶縁の旗印',
    iconUrl: null,
    effects: ['元素チャージ効率+20%', '元素爆発ダメージアップ'],
    route: 'Emblem of Severed Fate',
  );
  const golden = ArtifactSetDetail(
    id: '15037',
    name: '黄金の劇団',
    iconUrl: null,
    effects: ['元素スキルダメージ+20%'],
    route: 'Golden Troupe',
  );

  group('buildCharacterRecommendedArtifactSets', () {
    test('ranks akasha rates and resolves english route keys', () {
      final list = buildCharacterRecommendedArtifactSets(
        characterId: '10000052',
        characterName: '雷電将軍',
        sets: const [emblem, golden],
        akashaRates: {'Golden Troupe': 0.12, 'Emblem of Severed Fate': 0.88},
      );

      expect(list, hasLength(2));
      expect(list.first.set.name, '絶縁の旗印');
      expect(list.first.usageRate, 0.88);
      expect(list.first.isFromAkasha, isTrue);
      expect(list.last.set.name, '黄金の劇団');
    });

    test('fills from config when akasha is empty', () {
      final list = buildCharacterRecommendedArtifactSets(
        characterId: '10000052',
        characterName: '雷電将軍',
        sets: const [emblem, golden],
        configRecommendationsBySetName: {
          '絶縁の旗印': ['雷電将軍', '香菱'],
          '黄金の劇団': ['フリーナ'],
        },
      );

      expect(list, hasLength(1));
      expect(list.single.set.name, '絶縁の旗印');
      expect(list.single.usageRate, isNull);
      expect(list.single.source, 'config');
    });

    test('prefers akasha and does not duplicate config set', () {
      final list = buildCharacterRecommendedArtifactSets(
        characterId: '10000052',
        characterName: '雷電将軍',
        sets: const [emblem, golden],
        akashaRates: {'Emblem of Severed Fate': 0.9},
        configRecommendationsBySetName: {
          '絶縁の旗印': ['雷電将軍'],
          '黄金の劇団': ['雷電将軍'],
        },
      );

      expect(list.map((e) => e.set.id), ['15020', '15037']);
      expect(list.first.source, 'akasha');
      expect(list.last.source, 'config');
    });

    test('ignores akasha rates below minRate', () {
      final list = buildCharacterRecommendedArtifactSets(
        characterId: '10000052',
        characterName: '雷電将軍',
        sets: const [emblem],
        akashaRates: {'Emblem of Severed Fate': 0.02},
        minRate: 0.05,
      );

      expect(list, isEmpty);
    });
  });
}
