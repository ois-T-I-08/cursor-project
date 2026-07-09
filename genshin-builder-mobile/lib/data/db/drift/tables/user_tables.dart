import 'package:drift/drift.dart';

class UserProgressTable extends Table {
  @override
  String get tableName => 'user_progress';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get characterId => text()();
  IntColumn get level => integer().withDefault(const Constant(1))();
  IntColumn get ascension => integer().withDefault(const Constant(0))();
  IntColumn get constellation => integer().withDefault(const Constant(0))();
  IntColumn get talentNormal => integer().withDefault(const Constant(1))();
  IntColumn get talentSkill => integer().withDefault(const Constant(1))();
  IntColumn get talentBurst => integer().withDefault(const Constant(1))();
  TextColumn get weaponId => text().withDefault(const Constant(''))();
  TextColumn get weaponName => text().withDefault(const Constant(''))();
  IntColumn get weaponLevel => integer().withDefault(const Constant(1))();
  IntColumn get weaponRefinement => integer().withDefault(const Constant(1))();
  TextColumn get artifacts => text().withDefault(const Constant('{}'))();
  TextColumn get artifactScoreType => text().withDefault(const Constant(''))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get memo => text().withDefault(const Constant(''))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {userId, characterId},
      ];
}

class MaterialBookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceKey => text()();
  TextColumn get sourceLabel => text()();
  TextColumn get materialId => text()();
  TextColumn get name => text()();
  IntColumn get count => integer()();
  TextColumn get iconUrl => text().nullable()();
  TextColumn get characterId => text().nullable()();
  TextColumn get characterName => text().nullable()();
  TextColumn get characterIconUrl => text().nullable()();
  TextColumn get characterEmoji => text().nullable()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get status => text()();
  TextColumn get detail => text()();
  IntColumn get createdAt => integer()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
