class VersionStatus {
  const VersionStatus({
    this.masterDataVersion,
    this.artifactScoreWeightsVersion,
    this.updatedAt,
  });

  final String? masterDataVersion;
  final String? artifactScoreWeightsVersion;
  final DateTime? updatedAt;

  bool get hasAnyVersion =>
      (masterDataVersion?.isNotEmpty ?? false) ||
      (artifactScoreWeightsVersion?.isNotEmpty ?? false);
}
