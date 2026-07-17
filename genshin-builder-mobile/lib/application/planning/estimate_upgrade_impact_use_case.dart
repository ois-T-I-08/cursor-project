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
          reasons.add('レベル差が大きい（$diff）ため基礎ステータスへの影響が大きいです');
        } else if (diff >= 20) {
          impactScore = 0.20;
          reasons.add('レベル差は中程度です（$diff）');
        } else if (diff >= 10) {
          impactScore = 0.10;
          reasons.add('レベル差は小さめです（$diff）');
        } else {
          impactScore = 0.05;
          reasons.add('レベル差はごくわずかです');
        }
        areas.addAll(['baseStats', 'survivability']);
        break;

      case 'ascension':
        impactScore = 0.30;
        reasons.add('突破によりレベル上限が上がり、ステータスボーナスが得られます');
        reasons.add('突破固有効果でキャラ性能が大きく伸びることがあります');
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
        reasons.add('天賦レベルを上げると基礎倍率に直接反映されます');
        areas.add('damageOutput');
        break;

      case 'weapon':
        final diff = (option.toValue ?? 1) - (option.fromValue ?? 1);
        if (diff >= 40) {
          impactScore = 0.30;
          reasons.add('武器レベル差が大きいため基礎攻撃力への影響が大きいです');
        } else if (diff >= 20) {
          impactScore = 0.20;
          reasons.add('武器レベル差は中程度です');
        } else {
          impactScore = 0.10;
          reasons.add('武器レベル差は小さめです');
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
