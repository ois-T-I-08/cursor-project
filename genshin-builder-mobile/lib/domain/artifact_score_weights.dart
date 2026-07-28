class ArtifactStatWeights {
  const ArtifactStatWeights({
    required this.critRate,
    required this.critDamage,
    required this.atkPercent,
    required this.hpPercent,
    required this.defPercent,
    required this.elementalMastery,
    required this.energyRecharge,
  });

  final double critRate;
  final double critDamage;
  final double atkPercent;
  final double hpPercent;
  final double defPercent;
  final double elementalMastery;
  final double energyRecharge;

  factory ArtifactStatWeights.fromJson(Map<String, dynamic> json) =>
      ArtifactStatWeights(
        critRate: (json['critRate'] as num?)?.toDouble() ?? 2,
        critDamage: (json['critDamage'] as num?)?.toDouble() ?? 1,
        atkPercent: (json['atkPercent'] as num?)?.toDouble() ?? 1,
        hpPercent: (json['hpPercent'] as num?)?.toDouble() ?? 0,
        defPercent: (json['defPercent'] as num?)?.toDouble() ?? 0,
        elementalMastery: (json['elementalMastery'] as num?)?.toDouble() ?? 0,
        energyRecharge: (json['energyRecharge'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'critRate': critRate,
    'critDamage': critDamage,
    'atkPercent': atkPercent,
    'hpPercent': hpPercent,
    'defPercent': defPercent,
    'elementalMastery': elementalMastery,
    'energyRecharge': energyRecharge,
  };
}

class ArtifactScoreWeightProfile {
  const ArtifactScoreWeightProfile({
    required this.characterId,
    required this.name,
    required this.weights,
  });

  final String characterId;
  final String name;
  final ArtifactStatWeights weights;

  factory ArtifactScoreWeightProfile.fromJson(Map<String, dynamic> json) =>
      ArtifactScoreWeightProfile(
        characterId: json['characterId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        weights: ArtifactStatWeights.fromJson(
          json['weights'] as Map<String, dynamic>? ?? const {},
        ),
      );
}
