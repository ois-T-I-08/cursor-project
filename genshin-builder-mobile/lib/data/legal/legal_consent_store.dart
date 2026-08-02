import '../../domain/legal/legal_consent.dart';
import '../db/app_database.dart';

class LegalConsentStore {
  LegalConsentStore(this._db);

  final AppDatabase _db;

  Future<LegalConsentSnapshot> read() async {
    final privacy = await _db.getSetting(LegalConsentVersions.privacyPolicyKey);
    final terms = await _db.getSetting(LegalConsentVersions.termsKey);
    final hoyolab = await _db.getSetting(
      LegalConsentVersions.hoyolabDisclosureKey,
    );
    final atRaw = await _db.getSetting(LegalConsentVersions.acceptedAtKey);
    DateTime? at;
    if (atRaw != null && atRaw.isNotEmpty) {
      at = DateTime.tryParse(atRaw);
    }
    return LegalConsentSnapshot(
      acceptedPrivacyPolicyVersion: privacy,
      acceptedTermsVersion: terms,
      acceptedHoyolabDisclosureVersion: hoyolab,
      acceptedAt: at,
    );
  }

  /// Persists current policy versions after the user accepts the HoYoLAB disclosure.
  Future<void> acceptHoyolabDisclosure({DateTime? now}) async {
    final stamp = (now ?? DateTime.now().toUtc()).toIso8601String();
    await _db.setSetting(
      LegalConsentVersions.privacyPolicyKey,
      LegalConsentVersions.currentPrivacyPolicyVersion,
    );
    await _db.setSetting(
      LegalConsentVersions.termsKey,
      LegalConsentVersions.currentTermsVersion,
    );
    await _db.setSetting(
      LegalConsentVersions.hoyolabDisclosureKey,
      LegalConsentVersions.currentHoyolabDisclosureVersion,
    );
    await _db.setSetting(LegalConsentVersions.acceptedAtKey, stamp);
  }

  Future<bool> needsHoyolabDisclosure() async {
    final snap = await read();
    return !snap.hasCurrentHoyolabDisclosure;
  }
}
