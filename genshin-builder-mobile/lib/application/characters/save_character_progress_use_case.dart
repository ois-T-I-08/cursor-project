import '../../domain/models/master_models.dart';
import '../../domain/repositories/progress_mutation_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import 'character_detail_state.dart';

/// キャラ進捗の永続化。
class SaveCharacterProgressUseCase {
  const SaveCharacterProgressUseCase({
    required ProgressRepository progress,
    ProgressMutationRepository? mutation,
  })  : _progress = progress,
        _mutation = mutation;

  final ProgressRepository _progress;
  final ProgressMutationRepository? _mutation;

  Future<UserProgress> call({
    required UserProgress base,
    required CharacterDetailState state,
  }) async {
    final updated = base.copyWith(
      level: state.level,
      constellation: state.constellation,
      talentNormal: state.talentNormal,
      talentSkill: state.talentSkill,
      talentBurst: state.talentBurst,
      weaponLevel: state.weaponLevel,
      weaponId: state.weaponId,
      weaponName: state.weaponName,
      artifacts: state.artifacts,
      artifactCompleted: state.artifactCompleted,
    );
    final mutation = _mutation;
    if (mutation != null) {
      await mutation.saveWithEvents(
        progress: updated,
        before: base,
        userId: base.userId,
      );
    } else {
      await _progress.save(updated);
    }
    return updated;
  }
}
