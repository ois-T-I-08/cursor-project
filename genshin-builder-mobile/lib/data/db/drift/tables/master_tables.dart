import 'package:drift/drift.dart';

class Characters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get element => text()();
  TextColumn get weaponType => text()();
  IntColumn get rarity => integer()();
  TextColumn get region => text()();
  TextColumn get iconUrl => text()();
  TextColumn get scoreType => text().withDefault(const Constant('atk'))();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Weapons extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get weaponType => text()();
  IntColumn get rarity => integer()();
  TextColumn get iconUrl => text()();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Materials extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get rarity => integer().nullable()();
  TextColumn get iconUrl => text()();
  IntColumn get expValue => integer().nullable()();
  TextColumn get expTarget => text().nullable()();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class CharacterUpgrades extends Table {
  TextColumn get characterId => text()();
  TextColumn get promotes => text()();
  TextColumn get talents => text()();
  TextColumn get contentHash => text().withDefault(const Constant(''))();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {characterId};
}

class WeaponUpgrades extends Table {
  TextColumn get weaponId => text()();
  TextColumn get promotes => text()();
  TextColumn get levelUpItemIds => text().withDefault(const Constant('[]'))();
  TextColumn get contentHash => text().withDefault(const Constant(''))();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {weaponId};
}

class LevelExpSegments extends Table {
  TextColumn get id => text()();
  TextColumn get targetType => text()();
  IntColumn get rarity => integer().withDefault(const Constant(0))();
  IntColumn get fromLevel => integer()();
  IntColumn get toLevel => integer()();
  IntColumn get expRequired => integer()();
  IntColumn get moraRequired => integer().withDefault(const Constant(0))();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
