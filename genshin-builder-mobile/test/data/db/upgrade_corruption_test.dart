import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/drift/app_database.dart';

void main() {
  late DriftAppDatabase db;

  setUp(() async {
    db = await DriftAppDatabase.openInMemory();
  });

  tearDown(() => db.close());

  test('malformed character upgrade JSON is ignored safely', () async {
    await db.customStatement(
      'INSERT INTO character_upgrades '
      '(character_id, promotes, talents, content_hash, synced_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['bad-character', '{not-json', '{}', '', 0],
    );

    expect(
      await db.characterDao.getCharacterUpgrade('bad-character'),
      isNull,
    );
    expect(
      await db.characterDao.getAllCharacterUpgrades(),
      isNot(contains('bad-character')),
    );
  });

  test('malformed weapon upgrade JSON is ignored safely', () async {
    await db.customStatement(
      'INSERT INTO weapon_upgrades '
      '(weapon_id, promotes, level_up_item_ids, content_hash, synced_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['bad-weapon', '[]', '{not-json', '', 0],
    );

    expect(await db.characterDao.getWeaponUpgrade('bad-weapon'), isNull);
    expect(
      await db.characterDao.getAllWeaponUpgrades(),
      isNot(contains('bad-weapon')),
    );
  });
}
