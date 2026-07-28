import 'package:genshin_builder_mobile/data/akasha/akasha_artifact_set_usage.dart';
import 'package:genshin_builder_mobile/domain/artifacts/artifact_set_recommendations.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/providers/artifact_sets_page_providers.dart';
import 'package:flutter_test/flutter_test.dart';

MasterCharacter _char(String id, String name, {int rarity = 5}) =>
    MasterCharacter(
      id: id,
      name: name,
      element: '炎',
      rarity: rarity,
      weaponType: '片手剣',
      region: 'モンド',
      iconUrl: '',
    );

void main() {
  group('countArtifactSetsFromBuilds', () {
    test('counts sets with 2+ pieces only', () {
      final builds = [
        {
          'artifactSets': {
            'Emblem of Severed Fate': {'count': 4},
            "Gladiator's Finale": {'count': 1},
          },
        },
        {
          'artifactSets': {
            'Emblem of Severed Fate': {'count': 2},
            "Gladiator's Finale": {'count': 2},
          },
        },
      ];
      final counts = countArtifactSetsFromBuilds(builds);
      expect(counts['Emblem of Severed Fate'], 2);
      expect(counts["Gladiator's Finale"], 1);
    });
  });

  group('invertCharacterSetUsage', () {
    test('ranks characters by rate per set', () {
      final index = invertCharacterSetUsage(
        snapshots: [
          (
            characterId: '10000052',
            rates: {'Emblem of Severed Fate': 0.9},
            isRemote: true,
          ),
          (
            characterId: '10000023',
            rates: {'Emblem of Severed Fate': 0.4},
            isRemote: true,
          ),
          (
            characterId: 'x',
            rates: {'Emblem of Severed Fate': 0.01},
            isRemote: true,
          ),
        ],
        minRate: 0.05,
      );
      final hits = index['Emblem of Severed Fate']!;
      expect(hits.length, 2);
      expect(hits.first.characterId, '10000052');
      expect(hits.last.characterId, '10000023');
    });
  });

  group('selectArtifactRecommendationSampleIds', () {
    test('owned only: does not add rest of master roster', () {
      final owned = _char('10000023', '香菱', rarity: 4);
      final masters = [
        _char('10000052', '雷電将軍'),
        owned,
        _char('10000030', '鍾離'),
        ...List.generate(7, (i) => _char('extra_$i', 'Extra$i', rarity: 4)),
      ];

      final ids = selectArtifactRecommendationSampleIds(
        ownedIds: {owned.id},
        progressList: const [],
        allCharacters: masters,
      );
      expect(ids, [owned.id]);
    });

    test('includes progress characters with setName after owned', () {
      final owned = _char('owned', 'Owned');
      final progressed = _char('progress', 'Progress');
      final progress = UserProgress(
        id: 'p1',
        userId: 'u',
        characterId: progressed.id,
        artifactsJson: encodeArtifactState({
          ArtifactSlotKey.flower: const ArtifactPiece(setName: '絶縁の旗印'),
        }),
      );

      final ids = selectArtifactRecommendationSampleIds(
        ownedIds: {owned.id},
        progressList: [progress],
        allCharacters: [owned, progressed, _char('other', 'Other')],
      );
      expect(ids, [owned.id, progressed.id]);
    });

    test('caps at maxSampleIds with owned priority', () {
      final ownedIds = {for (var i = 0; i < 40; i++) 'owned_$i'};
      final masters = [for (final id in ownedIds) _char(id, id)];

      final ids = selectArtifactRecommendationSampleIds(
        ownedIds: ownedIds,
        progressList: const [],
        allCharacters: masters,
        maxSampleIds: kArtifactAkashaSampleLimit,
      );
      expect(ids.length, kArtifactAkashaSampleLimit);
      expect(ids.every((id) => ownedIds.contains(id)), isTrue);
    });

    test('empty owned and progress yields empty sample', () {
      final ids = selectArtifactRecommendationSampleIds(
        ownedIds: {},
        progressList: const [],
        allCharacters: [_char('a', 'A'), _char('b', 'B')],
      );
      expect(ids, isEmpty);
    });
  });
}
