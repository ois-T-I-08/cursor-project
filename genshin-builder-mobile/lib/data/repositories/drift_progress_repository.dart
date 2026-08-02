import '../../domain/models/master_models.dart';
import '../../domain/repositories/progress_repository.dart';
import '../db/app_database.dart';

class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this._db);

  final AppDatabase _db;

  @override
  Future<UserProgress> getOrCreate({
    required String userId,
    required String characterId,
    required String progressId,
  }) => _db.getOrCreateProgress(userId, characterId, progressId);

  @override
  Future<List<UserProgress>> getAll(String userId) =>
      _db.getAllProgress(userId);

  @override
  Future<void> save(UserProgress progress) => _db.upsertProgress(progress);
}
