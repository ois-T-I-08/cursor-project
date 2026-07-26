import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/growth_tables.dart';

part 'growth_dao.g.dart';

@DriftAccessor(tables: [
  GrowthGoals,
  UserMaterialInventory,
  SavedTeams,
  GrowthEvents,
])
class GrowthDao extends DatabaseAccessor<DriftAppDatabase>
    with _$GrowthDaoMixin {
  GrowthDao(super.db);

  // ── Growth Goals ──────────────────────────────────────────────

  Future<List<GrowthGoal>> goalsGetAll(String userId) =>
      (select(growthGoals)..where((t) => t.userId.equals(userId))).get();

  Future<GrowthGoal?> goalGetById(String id) =>
      (select(growthGoals)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Save a growth goal from domain fields (avoids Companion types in callers).
  Future<void> goalSave({
    required String id,
    required String userId,
    required String characterId,
    int? targetLevel,
    int? targetAscension,
    int? targetTalentNormal,
    int? targetTalentSkill,
    int? targetTalentBurst,
    String? targetWeaponId,
    int? targetWeaponLevel,
    int priority = 0,
    String status = 'active',
    String? memo,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) async {
    await into(growthGoals).insertOnConflictUpdate(
      GrowthGoalsCompanion(
        id: Value(id),
        userId: Value(userId),
        characterId: Value(characterId),
        targetLevel: Value(targetLevel),
        targetAscension: Value(targetAscension),
        targetTalentNormal: Value(targetTalentNormal),
        targetTalentSkill: Value(targetTalentSkill),
        targetTalentBurst: Value(targetTalentBurst),
        targetWeaponId: Value(targetWeaponId),
        targetWeaponLevel: Value(targetWeaponLevel),
        priority: Value(priority),
        status: Value(status),
        memo: Value(memo),
        createdAt: Value(createdAt?.millisecondsSinceEpoch),
        updatedAt: Value(updatedAt?.millisecondsSinceEpoch),
        completedAt: Value(completedAt?.millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> goalUpsert(Insertable<GrowthGoal> c) =>
      into(growthGoals).insertOnConflictUpdate(c);

  Future<void> goalDelete(String id) =>
      (delete(growthGoals)..where((t) => t.id.equals(id))).go();

  Future<void> goalsDeleteAllForUser(String userId) =>
      (delete(growthGoals)..where((t) => t.userId.equals(userId))).go();

  Future<void> inventoryDeleteAllForUser(String userId) =>
      (delete(userMaterialInventory)..where((t) => t.userId.equals(userId))).go();

  Future<void> teamsDeleteAllForUser(String userId) =>
      (delete(savedTeams)..where((t) => t.userId.equals(userId))).go();

  Future<void> eventsDeleteAllForUser(String userId) =>
      (delete(growthEvents)..where((t) => t.userId.equals(userId))).go();

  Future<void> clearAllPlanningDataForUser(String userId) async {
    await goalsDeleteAllForUser(userId);
    await inventoryDeleteAllForUser(userId);
    await teamsDeleteAllForUser(userId);
    await eventsDeleteAllForUser(userId);
  }

  Future<void> goalDeleteByCharacter(String userId, String characterId) =>
      (delete(growthGoals)
            ..where((t) => t.userId.equals(userId) & t.characterId.equals(characterId)))
          .go();

  // ── Material Inventory ────────────────────────────────────────

  Future<List<UserMaterialInventoryData>> inventoryGet(String userId) =>
      (select(userMaterialInventory)..where((t) => t.userId.equals(userId))).get();

  Future<void> inventorySetQuantity(String userId, String materialId, int quantity) async {
    await into(userMaterialInventory).insertOnConflictUpdate(
      UserMaterialInventoryCompanion(
        userId: Value(userId),
        materialId: Value(materialId),
        quantity: Value(quantity),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> inventoryUpsert(Insertable<UserMaterialInventoryData> c) =>
      into(userMaterialInventory).insertOnConflictUpdate(c);

  Future<void> inventoryDelete(String userId, String materialId) =>
      (delete(userMaterialInventory)
            ..where((t) => t.userId.equals(userId) & t.materialId.equals(materialId)))
          .go();

  // ── Saved Teams ───────────────────────────────────────────────

  Future<List<SavedTeam>> teamsGetAll(String userId) =>
      (select(savedTeams)..where((t) => t.userId.equals(userId))).get();

  Future<SavedTeam?> teamGetById(String id) =>
      (select(savedTeams)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> teamSave({
    required String id,
    required String userId,
    required String name,
    required String membersJson,
    String notes = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(savedTeams).insertOnConflictUpdate(
      SavedTeamsCompanion(
        id: Value(id),
        userId: Value(userId),
        name: Value(name),
        membersJson: Value(membersJson),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> teamUpsert(Insertable<SavedTeam> c) =>
      into(savedTeams).insertOnConflictUpdate(c);

  Future<void> teamDelete(String id) =>
      (delete(savedTeams)..where((t) => t.id.equals(id))).go();

  // ── Growth Events ─────────────────────────────────────────────

  Future<void> eventInsert(Insertable<GrowthEvent> c) =>
      into(growthEvents).insert(c, mode: InsertMode.insertOrIgnore);

  Future<void> eventsSaveAll(List<EventParams> events) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in events) {
      // InsertMode.insertOrIgnore silently skips UNIQUE constraint violations.
      await into(growthEvents).insert(
        GrowthEventsCompanion(
          eventId: Value(e.eventId),
          userId: Value(e.userId),
          characterId: Value(e.characterId),
          eventType: Value(e.eventType),
          beforeValue: Value(e.beforeValue),
          afterValue: Value(e.afterValue),
          source: Value(e.source),
          observedAt: Value(e.observedAt),
          createdAt: Value(now),
          dedupKey: Value(e.dedupKey),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<List<GrowthEvent>> eventsGetByUser(String userId, {int limit = 50, DateTime? beforeObservedAt, String? beforeEventId}) {
    var q = select(growthEvents)..where((t) => t.userId.equals(userId));
    if (beforeObservedAt != null && beforeEventId != null) {
      q = q..where((t) =>
            t.observedAt.isSmallerThanValue(beforeObservedAt.millisecondsSinceEpoch) |
            (t.observedAt.equals(beforeObservedAt.millisecondsSinceEpoch) &
             t.eventId.isSmallerThanValue(beforeEventId)));
    } else if (beforeObservedAt != null) {
      q = q..where((t) => t.observedAt.isSmallerThanValue(beforeObservedAt.millisecondsSinceEpoch));
    }
    q = q..orderBy([(t) => OrderingTerm(expression: t.observedAt, mode: OrderingMode.desc)]);
    q = q..orderBy([(t) => OrderingTerm(expression: t.eventId, mode: OrderingMode.desc)]);
    q = q..limit(limit);
    return q.get();
  }

  Future<List<GrowthEvent>> eventsGetByCharacter(
      String userId, String characterId) {
    return (select(growthEvents)
          ..where((t) => t.userId.equals(userId) & t.characterId.equals(characterId))
          ..orderBy([(t) => OrderingTerm(expression: t.observedAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<int> eventCountByDedupKey(String dedupKey) {
    return (selectOnly(growthEvents)
          ..addColumns([growthEvents.eventId])
          ..where(growthEvents.dedupKey.equals(dedupKey)))
        .map((row) => row.read(growthEvents.eventId))
        .get()
        .then((rows) => rows.length);
  }
}

/// Parameters for creating a growth event.
class EventParams {
  EventParams({
    required this.eventId,
    required this.userId,
    required this.characterId,
    required this.eventType,
    this.beforeValue,
    this.afterValue,
    this.source,
    required this.observedAt,
    required this.dedupKey,
  });

  final String eventId;
  final String userId;
  final String characterId;
  final String eventType;
  final String? beforeValue;
  final String? afterValue;
  final String? source;
  final int observedAt;
  final String dedupKey;
}
