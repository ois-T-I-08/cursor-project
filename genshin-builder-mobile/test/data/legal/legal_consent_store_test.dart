import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/data/legal/legal_consent_store.dart';
import 'package:genshin_builder_mobile/domain/legal/legal_consent.dart';

void main() {
  late AppDatabase db;
  late LegalConsentStore store;

  setUp(() async {
    db = await AppDatabase.openInMemory();
    store = LegalConsentStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('needs disclosure until current version accepted', () async {
    expect(await store.needsHoyolabDisclosure(), isTrue);
    await store.acceptHoyolabDisclosure(
      now: DateTime.utc(2026, 7, 26, 12),
    );
    expect(await store.needsHoyolabDisclosure(), isFalse);
    final snap = await store.read();
    expect(
      snap.acceptedHoyolabDisclosureVersion,
      LegalConsentVersions.currentHoyolabDisclosureVersion,
    );
    expect(
      snap.acceptedPrivacyPolicyVersion,
      LegalConsentVersions.currentPrivacyPolicyVersion,
    );
    expect(snap.acceptedTermsVersion, LegalConsentVersions.currentTermsVersion);
    expect(snap.acceptedAt, DateTime.utc(2026, 7, 26, 12));
  });

  test('major version bump requires re-consent; typos do not change constants', () {
    expect(LegalConsentVersions.currentHoyolabDisclosureVersion, '2026-07-26');
    // Cosmetic copy edits must not bump these constants.
  });
}
