/// Versioned legal / disclosure acceptance (non-secret; stored in AppSettings).
class LegalConsentVersions {
  const LegalConsentVersions._();

  /// Bump when Privacy Policy / Terms / HoYoLAB disclosure materially change.
  static const currentPrivacyPolicyVersion = '2026-07-26';
  static const currentTermsVersion = '2026-07-26';
  static const currentHoyolabDisclosureVersion = '2026-07-26';

  static const privacyPolicyKey = 'acceptedPrivacyPolicyVersion';
  static const termsKey = 'acceptedTermsVersion';
  static const hoyolabDisclosureKey = 'acceptedHoyolabDisclosureVersion';
  static const acceptedAtKey = 'acceptedAt';
}

class LegalConsentSnapshot {
  const LegalConsentSnapshot({
    this.acceptedPrivacyPolicyVersion,
    this.acceptedTermsVersion,
    this.acceptedHoyolabDisclosureVersion,
    this.acceptedAt,
  });

  final String? acceptedPrivacyPolicyVersion;
  final String? acceptedTermsVersion;
  final String? acceptedHoyolabDisclosureVersion;
  final DateTime? acceptedAt;

  bool get hasCurrentHoyolabDisclosure =>
      acceptedHoyolabDisclosureVersion ==
      LegalConsentVersions.currentHoyolabDisclosureVersion;
}
