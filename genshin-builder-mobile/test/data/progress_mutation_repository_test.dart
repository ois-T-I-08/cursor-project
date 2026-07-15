import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/data/repositories/progress_mutation_repository.dart';
import 'package:genshin_builder_mobile/domain/history/growth_event.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';

void main() {
  late AppDatabase db;
  late DriftProgressMutationRepository repository;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    repository = DriftProgressMutationRepository(db);
  });

  tearDown(() => db.close());

  test('saves progress and growth event for stable user id', () async {
    const before = UserProgress(
      id: 'progress-1',
      userId: 'uuid-user',
      characterId: '10000002',
      level: 1,
    );
    final after = before.copyWith(level: 20);

    final events = await repository.saveWithEvents(
      progress: after,
      before: before,
      userId: 'uuid-user',
    );

    expect(events, hasLength(1));
    expect(events.single.eventType, GrowthEventType.characterLevelChanged);
    expect(
      await db.getProgress('uuid-user', '10000002'),
      isA<UserProgress>().having((p) => p.level, 'level', 20),
    );
    expect(await db.growthDao.eventsGetByUser('uuid-user'), hasLength(1));
  });

  test('null before establishes baseline without event', () async {
    const progress = UserProgress(
      id: 'progress-1',
      userId: 'uuid-user',
      characterId: '10000002',
      level: 20,
    );

    expect(
      await repository.saveWithEvents(progress: progress, userId: 'uuid-user'),
      isEmpty,
    );
    expect(await db.growthDao.eventsGetByUser('uuid-user'), isEmpty);
  });

  for (final point in ProgressMutationPoint.values) {
    test('failure at ${point.name} rolls back and retry stores once', () async {
      const before = UserProgress(
        id: 'progress-fault',
        userId: 'uuid-user',
        characterId: '10000003',
        level: 1,
      );
      final after = before.copyWith(level: 20);
      await db.upsertProgress(before);

      final failing = DriftProgressMutationRepository(
        db,
        faultHook: (current) {
          if (current == point) throw StateError('forced failure');
        },
        now: () => DateTime.utc(2026, 7, 15),
        eventId: () => 'failed-event',
      );
      await expectLater(
        failing.saveWithEvents(
          progress: after,
          before: before,
          userId: 'uuid-user',
        ),
        throwsStateError,
      );

      expect(
        await db.getProgress('uuid-user', '10000003'),
        isA<UserProgress>().having((p) => p.level, 'level', 1),
      );
      expect(await db.growthDao.eventsGetByUser('uuid-user'), isEmpty);

      var eventNumber = 0;
      final retry = DriftProgressMutationRepository(
        db,
        now: () => DateTime.utc(2026, 7, 15),
        eventId: () => 'retry-event-${eventNumber++}',
      );
      await retry.saveWithEvents(
        progress: after,
        before: before,
        userId: 'uuid-user',
      );
      await retry.saveWithEvents(
        progress: after,
        before: before,
        userId: 'uuid-user',
      );

      expect(
        await db.getProgress('uuid-user', '10000003'),
        isA<UserProgress>().having((p) => p.level, 'level', 20),
      );
      expect(await db.growthDao.eventsGetByUser('uuid-user'), hasLength(1));
    });
  }

  test('rejects a mismatched user id before writing', () async {
    const progress = UserProgress(
      id: 'progress-owner',
      userId: 'owner',
      characterId: '10000004',
      level: 20,
    );

    await expectLater(
      repository.saveWithEvents(progress: progress, userId: 'other-user'),
      throwsArgumentError,
    );
    expect(await db.getAllProgress('owner'), isEmpty);
    expect(await db.growthDao.eventsGetByUser('owner'), isEmpty);
  });
}
