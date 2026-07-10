import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/data/models/master_models.dart';
import 'package:genshin_builder_mobile/data/repositories/progress_repository.dart';

void main() {
  late AppDatabase db;
  late ProgressRepository repo;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    repo = ProgressRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getOrCreate creates default progress then save updates level', () async {
    final created = await repo.getOrCreate(
      userId: 'user-1',
      characterId: '10000046',
      progressId: 'progress-1',
    );
    expect(created.userId, 'user-1');
    expect(created.characterId, '10000046');
    expect(created.level, 1);

    await repo.save(created.copyWith(level: 80, talentNormal: 8));

    final all = await repo.getAll('user-1');
    expect(all, hasLength(1));
    expect(all.single.level, 80);
    expect(all.single.talentNormal, 8);
  });

  test('getOrCreate is idempotent for same user and character', () async {
    final first = await repo.getOrCreate(
      userId: 'user-1',
      characterId: '10000002',
      progressId: 'a',
    );
    final second = await repo.getOrCreate(
      userId: 'user-1',
      characterId: '10000002',
      progressId: 'b',
    );
    expect(second.id, first.id);
  });
}
