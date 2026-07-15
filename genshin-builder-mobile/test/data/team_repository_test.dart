import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/data/repositories/drift_team_repository.dart';
import 'package:genshin_builder_mobile/domain/team/team_models.dart';

void main() {
  late AppDatabase db;
  late DriftTeamRepository repository;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    repository = DriftTeamRepository(db);
  });

  tearDown(() => db.close());

  test('saved team is isolated by stable local user id', () async {
    const team = Team(
      id: 'team-1',
      name: 'Team',
      members: [
        TeamMemberSlot(characterId: '10000002', position: 0),
      ],
    );

    await repository.save('uuid-user', team);

    expect(await repository.getAll('uuid-user'), [isA<Team>()]);
    expect(await repository.getAll('other-user'), isEmpty);
  });
}
