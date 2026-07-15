import 'package:drift/drift.dart';

import '../../../models/master_models.dart';
import '../app_database.dart';
import '../tables/user_tables.dart';

part 'progress_dao.g.dart';

@DriftAccessor(tables: [UserProgressTable, AppSettings, SyncLogs])
class ProgressDao extends DatabaseAccessor<DriftAppDatabase>
    with _$ProgressDaoMixin {
  ProgressDao(super.db);

  Future<void> upsertProgress(UserProgress p) async {
    await into(userProgressTable).insertOnConflictUpdate(
      _progressCompanion(p),
    );
  }

  Future<UserProgress?> getProgress(String userId, String characterId) async {
    final row = await (select(userProgressTable)
          ..where(
            (t) =>
                t.userId.equals(userId) & t.characterId.equals(characterId),
          ))
        .getSingleOrNull();
    return row == null ? null : _progressFromRow(row);
  }

  Future<List<UserProgress>> getAllProgress(String userId) async {
    final rows = await (select(userProgressTable)
          ..where((t) => t.userId.equals(userId)))
        .get();
    return rows.map(_progressFromRow).toList(growable: false);
  }

  Future<UserProgress> getOrCreateProgress(
    String userId,
    String characterId,
    String progressId,
  ) =>
      transaction(() async {
        final existing = await getProgress(userId, characterId);
        if (existing != null) return existing;
        final created = UserProgress(
          id: progressId,
          userId: userId,
          characterId: characterId,
        );
        await into(userProgressTable).insert(
          _progressCompanion(created),
          mode: InsertMode.insertOrIgnore,
        );
        final persisted = await getProgress(userId, characterId);
        if (persisted == null) {
          throw StateError('Failed to create user progress');
        }
        return persisted;
      });

  UserProgressTableCompanion _progressCompanion(UserProgress p) =>
      UserProgressTableCompanion.insert(
        id: p.id,
        userId: p.userId,
        characterId: p.characterId,
        level: Value(p.level),
        ascension: Value(p.ascension),
        constellation: Value(p.constellation),
        talentNormal: Value(p.talentNormal),
        talentSkill: Value(p.talentSkill),
        talentBurst: Value(p.talentBurst),
        weaponId: Value(p.weaponId),
        weaponName: Value(p.weaponName),
        weaponLevel: Value(p.weaponLevel),
        weaponRefinement: Value(p.weaponRefinement),
        artifacts: Value(p.artifactsJson),
        artifactScoreType: Value(p.artifactScoreType),
        isCompleted: Value(p.artifactCompleted),
        memo: Value(p.memo),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<void> insertSyncLog(String status, String detail) async {
    await into(syncLogs).insert(
      SyncLogsCompanion.insert(
        status: status,
        detail: detail,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<DateTime?> getLastSyncTime() async {
    final row = await (select(syncLogs)
          ..where((t) => t.status.isIn(['success', 'partial']))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(row.createdAt);
  }

  UserProgress _progressFromRow(UserProgressTableData row) => UserProgress(
        id: row.id,
        userId: row.userId,
        characterId: row.characterId,
        level: row.level,
        ascension: row.ascension,
        constellation: row.constellation,
        talentNormal: row.talentNormal,
        talentSkill: row.talentSkill,
        talentBurst: row.talentBurst,
        weaponId: row.weaponId,
        weaponName: row.weaponName,
        weaponLevel: row.weaponLevel,
        weaponRefinement: row.weaponRefinement,
        artifactsJson: row.artifacts,
        artifactScoreType: row.artifactScoreType,
        artifactCompleted: row.isCompleted,
        memo: row.memo,
      );
}
