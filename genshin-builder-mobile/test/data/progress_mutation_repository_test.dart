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
    expect(
      await db.growthDao.eventsGetByUser('uuid-user'),
      hasLength(1),
    );
  });

  test('null before establishes baseline without event', () async {
    const progress = UserProgress(
      id: 'progress-1',
      userId: 'uuid-user',
      characterId: '10000002',
      level: 20,
    );

    expect(
      await repository.saveWithEvents(
        progress: progress,
        userId: 'uuid-user',
      ),
      isEmpty,
    );
    expect(await db.growthDao.eventsGetByUser('uuid-user'), isEmpty);
  });
}
