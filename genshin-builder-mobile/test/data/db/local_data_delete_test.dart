import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/legal/legal_consent.dart';

void main() {
  test('deleteAllProgressForUser removes only progress rows', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);

    await db.upsertProgress(
      const UserProgress(
        id: 'p1',
        userId: 'u1',
        characterId: '10000089',
        level: 90,
        ascension: 6,
        constellation: 0,
        talentNormal: 1,
        talentSkill: 1,
        talentBurst: 1,
        weaponId: '',
        weaponName: '',
        weaponLevel: 1,
        weaponRefinement: 1,
        artifactsJson: '{}',
        artifactScoreType: '',
        artifactCompleted: false,
        memo: '',
      ),
    );
    await db.setSetting(LegalConsentVersions.hoyolabDisclosureKey, 'keep');
    expect((await db.getAllProgress('u1')).length, 1);

    await db.deleteAllProgressForUser('u1');
    expect(await db.getAllProgress('u1'), isEmpty);
    expect(
      await db.getSetting(LegalConsentVersions.hoyolabDisclosureKey),
      'keep',
    );
  });

  test('clearAllSettings removes consent keys (re-consent required)', () async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    await db.setSetting(
      LegalConsentVersions.hoyolabDisclosureKey,
      '2026-07-26',
    );
    await db.clearAllSettings();
    expect(
      await db.getSetting(LegalConsentVersions.hoyolabDisclosureKey),
      isNull,
    );
  });
}
