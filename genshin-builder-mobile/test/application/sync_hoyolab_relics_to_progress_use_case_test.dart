import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/hoyolab/sync_hoyolab_relics_to_progress_use_case.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';
import 'package:genshin_builder_mobile/domain/artifact_completion.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/repositories/progress_repository.dart';

class _FakeProgressRepository implements ProgressRepository {
  final Map<String, UserProgress> byCharacter = {};
  int saveCount = 0;

  @override
  Future<List<UserProgress>> getAll(String userId) async =>
      byCharacter.values.toList();

  @override
  Future<UserProgress> getOrCreate({
    required String userId,
    required String characterId,
    required String progressId,
  }) async {
    return byCharacter.putIfAbsent(
      characterId,
      () => UserProgress(
        id: progressId,
        userId: userId,
        characterId: characterId,
      ),
    );
  }

  @override
  Future<void> save(UserProgress progress) async {
    saveCount++;
    byCharacter[progress.characterId] = progress;
  }
}

void main() {
  test('persists merged relics into UserProgress.artifacts', () async {
    final repo = _FakeProgressRepository();
    final useCase = SyncHoyolabRelicsToProgressUseCase(
      progressRepository: repo,
    );

    final written = await useCase(
      userId: 'u1',
      builds: [
        const HoyolabCharacterBuild(
          id: '10000052',
          isOwned: true,
          relics: [
            GameRecordRelic(
              id: 'r1',
              name: '雷のような怒り',
              posName: '生の花',
              level: 20,
              setName: '絶縁の旗印',
            ),
          ],
        ),
      ],
    );

    expect(written, 1);
    expect(repo.saveCount, 1);
    final progress = repo.byCharacter['10000052']!;
    final flower = progress.artifacts[ArtifactSlotKey.flower]!;
    expect(flower.setName, '絶縁の旗印');
    expect(flower.level, 20);
    expect(isArtifactPieceEquipped(flower), isTrue);
  });

  test('skips builds without relics and skips unchanged saves', () async {
    final repo = _FakeProgressRepository();
    final useCase = SyncHoyolabRelicsToProgressUseCase(
      progressRepository: repo,
    );
    const build = HoyolabCharacterBuild(
      id: '10000002',
      isOwned: true,
      relics: [
        GameRecordRelic(
          id: 'r1',
          name: '花',
          posName: '生の花',
          level: 16,
          setName: '逆飛びの流星',
        ),
      ],
    );

    expect(await useCase(userId: 'u1', builds: [build]), 1);
    expect(await useCase(userId: 'u1', builds: [build]), 0);
    expect(
      await useCase(
        userId: 'u1',
        builds: const [
          HoyolabCharacterBuild(id: 'x', isOwned: true),
        ],
      ),
      0,
    );
  });
}
