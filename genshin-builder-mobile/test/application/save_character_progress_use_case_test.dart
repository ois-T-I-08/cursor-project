import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/characters/character_detail_state.dart';
import 'package:genshin_builder_mobile/application/characters/save_character_progress_use_case.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/repositories/progress_repository.dart';

class _FakeProgressRepository implements ProgressRepository {
  UserProgress? lastSaved;

  @override
  Future<List<UserProgress>> getAll(String userId) async => [];

  @override
  Future<UserProgress> getOrCreate({
    required String userId,
    required String characterId,
    required String progressId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> save(UserProgress progress) async {
    lastSaved = progress;
  }
}

void main() {
  test('SaveCharacterProgressUseCase persists edited fields', () async {
    final repo = _FakeProgressRepository();
    const base = UserProgress(
      id: 'p1',
      userId: 'u1',
      characterId: '10000046',
      level: 1,
    );
    final state = CharacterDetailState.initial().copyWith(
      level: 90,
      talentNormal: 9,
      talentSkill: 9,
      talentBurst: 9,
      weaponId: '11509',
      weaponName: '霧切',
      weaponLevel: 90,
      progress: base,
    );

    final saved = await SaveCharacterProgressUseCase(progress: repo).call(
      base: base,
      state: state,
    );

    expect(saved.level, 90);
    expect(saved.talentNormal, 9);
    expect(saved.weaponId, '11509');
    expect(repo.lastSaved?.level, 90);
  });
}
