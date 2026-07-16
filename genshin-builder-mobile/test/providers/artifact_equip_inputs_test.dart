import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/providers/artifact_sets_page_providers.dart';

void main() {
  group('buildArtifactEquipInputs', () {
    test('prefers character/detail relics over list and progress', () {
      final progress = [
        UserProgress(
          id: '1',
          userId: 'u',
          characterId: '10000052',
          artifactsJson: encodeArtifactState({
            ArtifactSlotKey.flower: const ArtifactPiece(setName: '旧セット'),
            ArtifactSlotKey.plume: const ArtifactPiece(setName: '旧セット'),
          }),
          artifactCompleted: true,
        ),
      ];
      final owned = {
        '10000052': const HoyolabOwnedCharacter(
          id: '10000052',
          name: '雷電将軍',
          level: 90,
          // list API は通常 relics 空
        ),
      };
      final details = {
        '10000052': const HoyolabCharacterBuild(
          id: '10000052',
          isOwned: true,
          level: 90,
          relics: [
            GameRecordRelic(
              id: '1',
              name: '花',
              posName: '生の花',
              level: 20,
              setName: '絶縁の旗印',
              iconUrl: 'https://example.com/UI_RelicIcon_15020_4.png',
            ),
            GameRecordRelic(
              id: '2',
              name: '羽',
              posName: '死の羽',
              level: 20,
              setName: '絶縁の旗印',
              iconUrl: 'https://example.com/UI_RelicIcon_15020_2.png',
            ),
          ],
        ),
      };

      final inputs = buildArtifactEquipInputs(
        ownedMap: owned,
        progressList: progress,
        detailBuilds: details,
      );

      expect(inputs, hasLength(1));
      expect(inputs.single.artifactCompleted, isTrue);
      expect(
        inputs.single.pieces.map((p) => p.setName),
        everyElement('絶縁の旗印'),
      );
    });

    test('falls back to progress when detail and list have no relics', () {
      final progress = [
        UserProgress(
          id: '1',
          userId: 'u',
          characterId: '10000030',
          artifactsJson: encodeArtifactState({
            ArtifactSlotKey.flower: const ArtifactPiece(setName: '千岩牢固'),
            ArtifactSlotKey.plume: const ArtifactPiece(setName: '千岩牢固'),
          }),
        ),
      ];
      final owned = {
        '10000030': const HoyolabOwnedCharacter(
          id: '10000030',
          name: '鍾離',
          level: 90,
        ),
      };

      final inputs = buildArtifactEquipInputs(
        ownedMap: owned,
        progressList: progress,
        detailBuilds: const {},
      );

      expect(inputs.single.pieces.map((p) => p.setName), everyElement('千岩牢固'));
    });

    test('maps traveler hoyolab id to master id with element suffix', () {
      const traveler = MasterCharacter(
        id: '10000005-anemo',
        name: '旅人',
        element: '風',
        rarity: 5,
        weaponType: '片手剣',
        region: 'その他',
        iconUrl: '',
      );
      final details = {
        '10000005': const HoyolabCharacterBuild(
          id: '10000005',
          isOwned: true,
          relics: [
            GameRecordRelic(
              id: '1',
              name: '花',
              posName: '生の花',
              level: 20,
              setName: '翠緑の影',
            ),
            GameRecordRelic(
              id: '2',
              name: '羽',
              posName: '死の羽',
              level: 20,
              setName: '翠緑の影',
            ),
          ],
        ),
      };

      final inputs = buildArtifactEquipInputs(
        ownedMap: const {},
        progressList: const [],
        detailBuilds: details,
        charactersById: {traveler.id: traveler},
      );

      expect(inputs.single.characterId, '10000005-anemo');
    });
  });

  group('resolveMasterCharacterId', () {
    test('returns direct id when present', () {
      final byId = {
        '10000052': const MasterCharacter(
          id: '10000052',
          name: '雷電将軍',
          element: '雷',
          rarity: 5,
          weaponType: '長柄武器',
          region: '稲妻',
          iconUrl: '',
        ),
      };
      expect(resolveMasterCharacterId('10000052', byId), '10000052');
    });
  });
}
