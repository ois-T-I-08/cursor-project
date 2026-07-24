import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/domain/battle_statistics/battle_statistics.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';

void main() {
  const evaluator = BattleTeamAvailabilityEvaluator();
  const team = RemoteBattleTeam(
    teamKey: '1:2:3:4',
    members: ['1', '2', '3', '4'],
    usageRate: 0.5,
  );
  const known = {'1', '2', '3', '4'};

  test('all sufficiently built members are ready', () {
    final progress = {
      for (final id in team.members) id: _progress(id, ready: true),
    };
    final result = evaluator.evaluate(
      team: team,
      knownCharacterIds: known,
      progressByCharacterId: progress,
    );
    expect(result.availability, BattleTeamAvailability.ready);
    expect(
      result.members.map((member) => member.availability),
      everyElement(BattleMemberAvailability.ready),
    );
  });

  test('owned but insufficient builds are kept separate from usage rate', () {
    final progress = {
      for (final id in team.members) id: _progress(id, ready: false),
    };
    final result = evaluator.evaluate(
      team: team,
      knownCharacterIds: known,
      progressByCharacterId: progress,
    );
    expect(result.availability, BattleTeamAvailability.needsBuild);
    expect(result.members.first.availability, BattleMemberAvailability.owned);
  });

  test('partially built members are underbuilt', () {
    final progress = {
      for (final id in team.members) id: _progress(id, level: 70),
    };
    final result = evaluator.evaluate(
      team: team,
      knownCharacterIds: known,
      progressByCharacterId: progress,
    );
    expect(result.availability, BattleTeamAvailability.needsBuild);
    expect(
      result.members.map((member) => member.availability),
      everyElement(BattleMemberAvailability.underbuilt),
    );
  });

  test('one absent character yields missingOne', () {
    final progress = {
      for (final id in team.members.take(3)) id: _progress(id, ready: true),
    };
    final result = evaluator.evaluate(
      team: team,
      knownCharacterIds: known,
      progressByCharacterId: progress,
    );
    expect(result.availability, BattleTeamAvailability.missingOne);
    expect(result.members.last.availability, BattleMemberAvailability.missing);
  });

  test('unknown master IDs remain unknown instead of being guessed', () {
    final result = evaluator.evaluate(
      team: team,
      knownCharacterIds: const {'1', '2', '3'},
      progressByCharacterId: {
        for (final id in team.members) id: _progress(id, ready: true),
      },
    );
    expect(result.availability, BattleTeamAvailability.missingOne);
    expect(result.members.last.availability, BattleMemberAvailability.unknown);
  });
}

UserProgress _progress(String id, {bool ready = false, int? level}) {
  return UserProgress(
    id: 'progress-$id',
    userId: 'local',
    characterId: id,
    level: level ?? (ready ? 90 : 1),
    ascension: ready ? 6 : 0,
    talentNormal: ready ? 6 : 1,
    talentSkill: ready ? 9 : 1,
    talentBurst: ready ? 9 : 1,
    weaponId: ready ? 'weapon' : '',
    weaponLevel: ready ? 90 : 1,
    artifactCompleted: ready,
  );
}
