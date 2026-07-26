import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/db/app_database.dart';
import 'package:genshin_builder_mobile/data/legal/legal_consent_store.dart';
import 'package:genshin_builder_mobile/domain/legal/legal_consent.dart';

/// Mirrors HoyolabSettingsScreen._startLogin gate: disclosure before login.
class _HoyolabLoginGate {
  _HoyolabLoginGate(this.store);

  final LegalConsentStore store;
  var disclosureShown = false;
  var loginStarted = false;
  var networkStarted = false;

  Future<bool> startLogin({required bool userAcceptsDisclosure}) async {
    if (await store.needsHoyolabDisclosure()) {
      disclosureShown = true;
      if (!userAcceptsDisclosure) {
        return false;
      }
      await store.acceptHoyolabDisclosure();
    }
    // Only after accept may WebView / HoYoLAB APIs start.
    loginStarted = true;
    networkStarted = true;
    return true;
  }
}

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

  test('cancel: no login / network before accept', () async {
    final gate = _HoyolabLoginGate(store);
    final ok = await gate.startLogin(userAcceptsDisclosure: false);
    expect(ok, isFalse);
    expect(gate.disclosureShown, isTrue);
    expect(gate.loginStarted, isFalse);
    expect(gate.networkStarted, isFalse);
    expect(await store.needsHoyolabDisclosure(), isTrue);
  });

  test('accept: login starts only after disclosure stored', () async {
    final gate = _HoyolabLoginGate(store);
    final ok = await gate.startLogin(userAcceptsDisclosure: true);
    expect(ok, isTrue);
    expect(gate.loginStarted, isTrue);
    expect(await store.needsHoyolabDisclosure(), isFalse);
    expect(
      (await store.read()).acceptedHoyolabDisclosureVersion,
      LegalConsentVersions.currentHoyolabDisclosureVersion,
    );
  });

  test('stale disclosure version requires re-consent (major change)', () async {
    await db.setSetting(
      LegalConsentVersions.hoyolabDisclosureKey,
      '2020-01-01',
    );
    expect(await store.needsHoyolabDisclosure(), isTrue);
  });

  test('same version does not require re-consent (cosmetic edits)', () async {
    await store.acceptHoyolabDisclosure();
    expect(await store.needsHoyolabDisclosure(), isFalse);
    // Typos / layout-only edits must not bump LegalConsentVersions constants.
    expect(LegalConsentVersions.currentHoyolabDisclosureVersion, '2026-07-26');
  });
}
