import '../../domain/planning/growth_goal.dart';
import '../../domain/repositories/growth_goal_repository.dart';
import '../db/app_database_facade.dart';

class DriftGrowthGoalRepository implements GrowthGoalRepository {
  DriftGrowthGoalRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<GrowthGoal>> getAll(String userId) async =>
      (await _db.growthDao.goalsGetAll(userId)).map(_toDomain).toList();

  @override
  Future<GrowthGoal?> getById(String id) async {
    final row = await _db.growthDao.goalGetById(id);
    return row != null ? _toDomain(row) : null;
  }

  @override
  Future<void> save(GrowthGoal g) => _db.growthDao.goalSave(
    id: g.id,
    userId: g.userId,
    characterId: g.characterId,
    targetLevel: g.targetLevel,
    targetAscension: g.targetAscension,
    targetTalentNormal: g.targetTalentNormal,
    targetTalentSkill: g.targetTalentSkill,
    targetTalentBurst: g.targetTalentBurst,
    targetWeaponId: g.targetWeaponId,
    targetWeaponLevel: g.targetWeaponLevel,
    priority: g.priority,
    status: g.status.name,
    memo: g.memo,
    createdAt: g.createdAt,
    updatedAt: g.updatedAt,
    completedAt: g.completedAt,
  );

  @override
  Future<void> delete(String id) => _db.growthDao.goalDelete(id);

  @override
  Future<void> deleteByCharacterId(String userId, String characterId) =>
      _db.growthDao.goalDeleteByCharacter(userId, characterId);

  GrowthGoal _toDomain(dynamic row) => GrowthGoal(
    id: row.id as String,
    userId: row.userId as String,
    characterId: (row.characterId as String?) ?? '',
    targetLevel: row.targetLevel as int?,
    targetAscension: row.targetAscension as int?,
    targetTalentNormal: row.targetTalentNormal as int?,
    targetTalentSkill: row.targetTalentSkill as int?,
    targetTalentBurst: row.targetTalentBurst as int?,
    targetWeaponId: row.targetWeaponId as String?,
    targetWeaponLevel: row.targetWeaponLevel as int?,
    priority: (row.priority as int?) ?? 0,
    status: GrowthGoalStatus.values.firstWhere(
      (e) => e.name == (row.status as String?),
      orElse: () => GrowthGoalStatus.active,
    ),
    memo: row.memo as String?,
    createdAt:
        row.createdAt != null
            ? DateTime.fromMillisecondsSinceEpoch(row.createdAt as int)
            : null,
    updatedAt:
        row.updatedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(row.updatedAt as int)
            : null,
    completedAt:
        row.completedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(row.completedAt as int)
            : null,
  );
}
