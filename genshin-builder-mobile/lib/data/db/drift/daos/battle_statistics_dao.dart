import 'package:drift/drift.dart';

import '../../../../domain/battle_statistics/battle_statistics.dart';
import '../app_database.dart';
import '../tables/battle_statistics_tables.dart';

part 'battle_statistics_dao.g.dart';

@DriftAccessor(
  tables: [
    RemoteBattleStatsManifests,
    RemoteBattleTeams,
    RemoteBattleTeamMembers,
    RemoteBattleCharacterUsages,
    RemoteBattleSyncStates,
  ],
)
class BattleStatisticsDao extends DatabaseAccessor<DriftAppDatabase>
    with _$BattleStatisticsDaoMixin {
  BattleStatisticsDao(super.db);

  Future<RemoteBattleStatsManifest?> readManifest(String contentType) {
    return (select(remoteBattleStatsManifests)
      ..where((row) => row.contentType.equals(contentType))).getSingleOrNull();
  }

  Future<void> replaceBundle(BattleStatsBundle bundle) async {
    final contentType = bundle.contentType.name;
    await transaction(() async {
      final oldTeams =
          await (select(remoteBattleTeams)
            ..where((row) => row.contentType.equals(contentType))).get();
      if (oldTeams.isNotEmpty) {
        await (delete(remoteBattleTeamMembers)..where(
          (row) => row.teamId.isIn(oldTeams.map((team) => team.id)),
        )).go();
      }
      await (delete(remoteBattleTeams)
        ..where((row) => row.contentType.equals(contentType))).go();
      await (delete(remoteBattleCharacterUsages)
        ..where((row) => row.contentType.equals(contentType))).go();

      await batch((batch) {
        for (var teamIndex = 0; teamIndex < bundle.teams.length; teamIndex++) {
          final team = bundle.teams[teamIndex];
          final teamId = '$contentType:${bundle.revision}:$teamIndex';
          batch.insert(
            remoteBattleTeams,
            RemoteBattleTeamsCompanion.insert(
              id: teamId,
              contentType: contentType,
              revision: bundle.revision,
              teamKey: team.teamKey,
              usageRate: team.usageRate,
              usageCount: Value(team.usageCount),
              rank: Value(team.rank),
              side: Value(team.side),
              stageKey: Value(team.stageKey),
              sampleSize: Value(team.sampleSize),
            ),
          );
          for (
            var memberIndex = 0;
            memberIndex < team.members.length;
            memberIndex++
          ) {
            batch.insert(
              remoteBattleTeamMembers,
              RemoteBattleTeamMembersCompanion.insert(
                teamId: teamId,
                characterId: team.members[memberIndex],
                slot: memberIndex,
                displayOrder: memberIndex,
              ),
            );
          }
        }
        for (var index = 0; index < bundle.characters.length; index++) {
          final character = bundle.characters[index];
          batch.insert(
            remoteBattleCharacterUsages,
            RemoteBattleCharacterUsagesCompanion.insert(
              id: '$contentType:${bundle.revision}:$index',
              contentType: contentType,
              revision: bundle.revision,
              characterId: character.characterId,
              usageRate: character.usageRate,
              usageCount: Value(character.usageCount),
              rank: Value(character.rank),
              side: Value(character.side),
              ownershipRate: Value(character.ownershipRate),
              usageAmongOwnersRate: Value(character.usageAmongOwnersRate),
              sampleSize: Value(character.sampleSize),
            ),
          );
        }
      });

      await into(remoteBattleStatsManifests).insertOnConflictUpdate(
        RemoteBattleStatsManifestsCompanion.insert(
          contentType: contentType,
          seasonId: bundle.seasonId,
          revision: bundle.revision,
          payloadHash: bundle.payloadHash,
          schemaVersion: bundle.schemaVersion,
          sourceUpdatedAt: bundle.sourceUpdatedAt.millisecondsSinceEpoch,
          syncedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  Future<List<RemoteBattleTeam>> readTeams(String contentType) async {
    final teamRows =
        await (select(remoteBattleTeams)
              ..where((row) => row.contentType.equals(contentType))
              ..orderBy([(row) => OrderingTerm.desc(row.usageRate)]))
            .get();
    final result = <RemoteBattleTeam>[];
    for (final team in teamRows) {
      final members =
          await (select(remoteBattleTeamMembers)
                ..where((row) => row.teamId.equals(team.id))
                ..orderBy([(row) => OrderingTerm.asc(row.displayOrder)]))
              .get();
      result.add(
        RemoteBattleTeam(
          teamKey: team.teamKey,
          members: members.map((member) => member.characterId).toList(),
          usageRate: team.usageRate,
          usageCount: team.usageCount,
          rank: team.rank,
          side: team.side,
          stageKey: team.stageKey,
          sampleSize: team.sampleSize,
        ),
      );
    }
    return result;
  }

  Future<void> recordSyncState(
    String contentType,
    RemoteBattleStatsState state, {
    String? errorCode,
  }) async {
    final previous =
        await (select(remoteBattleSyncStates)..where(
          (row) => row.contentType.equals(contentType),
        )).getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(remoteBattleSyncStates).insertOnConflictUpdate(
      RemoteBattleSyncStatesCompanion.insert(
        contentType: contentType,
        state: state.name,
        errorCode: Value(errorCode),
        lastAttemptAt: now,
        lastSuccessAt: Value(
          state == RemoteBattleStatsState.valid ? now : previous?.lastSuccessAt,
        ),
      ),
    );
  }
}
