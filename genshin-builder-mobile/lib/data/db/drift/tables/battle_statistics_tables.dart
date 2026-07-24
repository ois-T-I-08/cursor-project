import 'package:drift/drift.dart';

class RemoteBattleStatsManifests extends Table {
  TextColumn get contentType => text()();
  TextColumn get seasonId => text()();
  IntColumn get revision => integer()();
  TextColumn get payloadHash => text()();
  IntColumn get schemaVersion => integer()();
  IntColumn get sourceUpdatedAt => integer()();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {contentType};
}

@DataClassName('RemoteBattleTeamRow')
class RemoteBattleTeams extends Table {
  TextColumn get id => text()();
  TextColumn get contentType => text()();
  IntColumn get revision => integer()();
  TextColumn get teamKey => text()();
  RealColumn get usageRate => real()();
  IntColumn get usageCount => integer().nullable()();
  IntColumn get rank => integer().nullable()();
  TextColumn get side => text().nullable()();
  TextColumn get stageKey => text().nullable()();
  IntColumn get sampleSize => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class RemoteBattleTeamMembers extends Table {
  TextColumn get teamId => text()();
  TextColumn get characterId => text()();
  IntColumn get slot => integer()();
  IntColumn get displayOrder => integer()();

  @override
  Set<Column> get primaryKey => {teamId, characterId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {teamId, slot},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (team_id) REFERENCES remote_battle_teams (id) '
        'ON DELETE CASCADE',
  ];
}

@DataClassName('RemoteBattleCharacterUsageRow')
class RemoteBattleCharacterUsages extends Table {
  TextColumn get id => text()();
  TextColumn get contentType => text()();
  IntColumn get revision => integer()();
  TextColumn get characterId => text()();
  RealColumn get usageRate => real()();
  IntColumn get usageCount => integer().nullable()();
  IntColumn get rank => integer().nullable()();
  TextColumn get side => text().nullable()();
  RealColumn get ownershipRate => real().nullable()();
  RealColumn get usageAmongOwnersRate => real().nullable()();
  IntColumn get sampleSize => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class RemoteBattleSyncStates extends Table {
  TextColumn get contentType => text()();
  TextColumn get state => text()();
  TextColumn get errorCode => text().nullable()();
  IntColumn get lastAttemptAt => integer()();
  IntColumn get lastSuccessAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {contentType};
}
