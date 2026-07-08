import '../db/app_database.dart';
import '../models/master_models.dart';

class ProgressRepository {
  ProgressRepository(this._db);

  final AppDatabase _db;

  Future<UserProgress> getOrCreate({
    required String userId,
    required String characterId,
    required String progressId,
  }) =>
      _db.getOrCreateProgress(userId, characterId, progressId);

  Future<void> save(UserProgress progress) => _db.upsertProgress(progress);
}
