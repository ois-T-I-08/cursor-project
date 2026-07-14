import '../../domain/planning/upgrade_option.dart';
import '../../domain/recommendation/recommendation.dart';

/// Estimates relative impact of an UpgradeOption.
///
/// Phase 3B initial version: rule-based relative assessment.
/// No character roles, no DPS simulation, no enemy stats.
class EstimateUpgradeImpactUseCase {
  const EstimateUpgradeImpactUseCase();

  static const ruleVersion = '1';

  static const _excludedFactors = [
    'enemyDefense',
    'enemyResistance',
    'elementalReactions',
    'buffsDebuffs',
    'teamRotation',
    'weaponPassive',
    'characterConstellation',
    'energyRecharge',
    'snapshotTiming',
  ];

  UpgradeImpact call({required UpgradeOption option}) {
    final reasons = <String>[];
    var impactScore = 0.0;
    final areas = <String>[];

    switch (option.optionType) {
      case 'level':
        final diff = (option.toValue ?? 1) - (option.fromValue ?? 1);
        if (diff >= 40) {
          impactScore = 0.35;
          reasons.add(
            'Large level gap ($diff levels) has significant base stat impact',
          );
        } else if (diff >= 20) {
          impactScore = 0.20;
          reasons.add('Moderate level gap ($diff levels)');
        } else if (diff >= 10) {
          impactScore = 0.10;
          reasons.add('Small level gap ($diff levels)');
        } else {
          impactScore = 0.05;
          reasons.add('Minimal level gap');
        }
        areas.addAll(['baseStats', 'survivability']);
        break;

      case 'ascension':
        impactScore = 0.30;
        reasons.add(
          'Ascension unlocks higher level cap and grants bonus stats',
        );
        reasons.add(
          'Ascension passives may significantly boost character performance',
        );
        areas.addAll(['baseStats', 'survivability', 'specialStat']);
        break;

      case 'talentNormal':
      case 'talentSkill':
      case 'talentBurst':
        final diff = (option.toValue ?? 1) - (option.fromValue ?? 1);
        if (diff >= 4) {
          impactScore = 0.30;
        } else if (diff >= 2) {
          impactScore = 0.20;
        } else {
          impactScore = 0.10;
        }
        reasons.add('Talent level increase directly increases base multiplier');
        areas.add('damageOutput');
        break;

      case 'weapon':
        final diff = (option.toValue ?? 1) - (option.fromValue ?? 1);
        if (diff >= 40) {
          impactScore = 0.30;
          reasons.add('Large weapon level gap has significant base ATK impact');
        } else if (diff >= 20) {
          impactScore = 0.20;
          reasons.add('Moderate weapon level gap');
        } else {
          impactScore = 0.10;
          reasons.add('Small weapon level gap');
        }
        areas.addAll(['baseStats', 'damageOutput']);
        break;
    }

    final band = toBand(impactScore);

    return UpgradeImpact(
      impactScore: impactScore,
      impactBand: band,
      affectedAreas: areas,
      reasons: reasons,
      confidence:
          RecommendationConfidence.low, // Phase 3B: no roles, no combat sim
      calculationMode: CalculationMode.relativeImpactOnly,
      excludedFactors: _excludedFactors,
      ruleVersion: ruleVersion,
    );
  }

  /// Public for testing.
  static ImpactBand toBand(double score) {
    if (score >= 0.30) return ImpactBand.high;
    if (score >= 0.20) return ImpactBand.medium;
    if (score >= 0.10) return ImpactBand.low;
    if (score > 0) return ImpactBand.minimal;
    return ImpactBand.unknown;
  }
}
