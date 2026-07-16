import 'package:uuid/uuid.dart';

import '../../data/hoyolab/hoyolab_relic_sync.dart';
import '../../data/hoyolab/models/hoyolab_character_build.dart';
import '../../domain/repositories/progress_repository.dart';

/// Persists HoYoLAB relic loads into [UserProgress.artifacts].
///
/// Character detail already does this on open; this use case enables the same
/// write path from batch prefetch / account snapshot without opening detail.
class SyncHoyolabRelicsToProgressUseCase {
  SyncHoyolabRelicsToProgressUseCase({
    required ProgressRepository progressRepository,
    Uuid? uuid,
  })  : _progressRepository = progressRepository,
        _uuid = uuid ?? const Uuid();

  final ProgressRepository _progressRepository;
  final Uuid _uuid;

  /// Returns how many characters had artifacts written (JSON changed).
  Future<int> call({
    required String userId,
    required Iterable<HoyolabCharacterBuild> builds,
  }) async {
    var written = 0;
    for (final build in builds) {
      if (!build.isOwned || build.relics.isEmpty) continue;
      final existing = await _progressRepository.getOrCreate(
        userId: userId,
        characterId: build.id,
        progressId: _uuid.v4(),
      );
      final merged = mergeRelicsFromHoyolab(
        local: existing.artifacts,
        relics: build.relics,
      );
      final next = existing.copyWith(artifacts: merged);
      if (next.artifactsJson == existing.artifactsJson) continue;
      await _progressRepository.save(next);
      written++;
    }
    return written;
  }
}
