import '../../domain/history/growth_event.dart';
import '../../domain/repositories/growth_event_repository.dart';
import '../db/app_database_facade.dart';
import '../db/drift/daos/growth_dao.dart';

class DriftGrowthEventRepository implements GrowthEventRepository {
  DriftGrowthEventRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> saveAll(List<GrowthEvent> events) => _db.growthDao.eventsSaveAll(
    events
        .map(
          (e) => EventParams(
            eventId: e.eventId,
            userId: e.userId,
            characterId: e.characterId,
            eventType: e.eventType.name,
            beforeValue: e.beforeValue,
            afterValue: e.afterValue,
            source: e.source,
            observedAt: e.observedAt.millisecondsSinceEpoch,
            dedupKey: e.dedupKey,
          ),
        )
        .toList(),
  );

  @override
  Future<List<GrowthEvent>> getByUser(
    String userId, {
    int limit = 50,
    GrowthEventCursor? cursor,
  }) async {
    final rows = await _db.growthDao.eventsGetByUser(
      userId,
      limit: limit,
      beforeObservedAt: cursor?.observedAt,
      beforeEventId: cursor?.eventId,
    );
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<GrowthEvent>> getByCharacter(
    String userId,
    String characterId,
  ) async {
    final rows = await _db.growthDao.eventsGetByCharacter(userId, characterId);
    return rows.map(_toDomain).toList();
  }

  @override
  Future<bool> existsByDedupKey(String dedupKey) async {
    final count = await _db.growthDao.eventCountByDedupKey(dedupKey);
    return count > 0;
  }

  GrowthEvent _toDomain(dynamic row) => GrowthEvent(
    eventId: row.eventId as String,
    userId: row.userId as String,
    characterId: (row.characterId as String?) ?? '',
    eventType: GrowthEventType.values.firstWhere(
      (t) => t.name == (row.eventType as String),
      orElse: () => GrowthEventType.characterLevelChanged,
    ),
    beforeValue: row.beforeValue as String?,
    afterValue: row.afterValue as String?,
    source: row.source as String?,
    observedAt: DateTime.fromMillisecondsSinceEpoch(row.observedAt as int),
    createdAt:
        row.createdAt != null
            ? DateTime.fromMillisecondsSinceEpoch(row.createdAt as int)
            : null,
    dedupKey: row.dedupKey as String,
  );
}
