import '../../domain/account/account_snapshot.dart';
import '../../domain/planning/investment_diagnosis.dart';
import '../../domain/recommendation/recommendation.dart';

/// Diagnoses character investment (under/over-investment) without assuming roles.
class DiagnoseCharacterInvestmentUseCase {
  const DiagnoseCharacterInvestmentUseCase();

  InvestmentDiagnosis call({
    required AccountSnapshot snapshot,
    required String characterId,
    DateTime? generatedAt,
  }) {
    final char = snapshot.characters.where((c) => c.characterId == characterId).firstOrNull;
    if (char == null || !char.isOwned) {
      return InvestmentDiagnosis(
        characterId: characterId,
        generatedAt: generatedAt ?? DateTime.now(),
      );
    }

    final findings = <DiagnosisFinding>[];
    final missingData = snapshot.missingData.toList();

    // Get goals for this character
    final charGoals = snapshot.activeGoals
        .where((g) => g.characterId == characterId)
        .toList();

    for (final goal in charGoals) {
      // Level below goal
      if (goal.targetLevel != null && char.level < goal.targetLevel!) {
        findings.add(DiagnosisFinding(
          type: DiagnosisType.levelBelowGoal,
          severity: DiagnosisSeverity.warning,
          title: 'Lv.${char.level} → Lv.${goal.targetLevel}',
          explanation: 'Character level is below the growth goal target.',
          characterId: characterId,
          relatedGoalId: goal.id,
          currentValue: '${char.level}',
          targetValue: '${goal.targetLevel}',
          recommendation: 'Prioritize leveling to reach the growth goal target.',
          confidence: RecommendationConfidence.high,
          completeness: snapshot.completeness,
        ));
      }

      // Talent below goal
      for (final talentCheck in [
        ('Normal Attack', goal.targetTalentNormal, char.talentNormal),
        ('Elemental Skill', goal.targetTalentSkill, char.talentSkill),
        ('Elemental Burst', goal.targetTalentBurst, char.talentBurst),
      ]) {
        final label = talentCheck.$1;
        final target = talentCheck.$2;
        final current = talentCheck.$3;
        if (target != null && current < target) {
          findings.add(DiagnosisFinding(
            type: DiagnosisType.talentBelowGoal,
            severity: DiagnosisSeverity.warning,
            title: '$label Lv.$current → Lv.$target',
            explanation: 'Talent level is below the growth goal target.',
            characterId: characterId,
            relatedGoalId: goal.id,
            currentValue: '$current',
            targetValue: '$target',
            recommendation: 'Farm talent materials to reach the goal.',
            confidence: RecommendationConfidence.high,
          ));
        }
      }

      // Weapon below goal
      if (goal.targetWeaponLevel != null && char.weaponLevel < goal.targetWeaponLevel!) {
        findings.add(DiagnosisFinding(
          type: DiagnosisType.weaponBelowGoal,
          severity: DiagnosisSeverity.warning,
          title: 'Weapon Lv.${char.weaponLevel} → Lv.${goal.targetWeaponLevel}',
          explanation: 'Weapon level is below the growth goal target.',
          characterId: characterId,
          relatedGoalId: goal.id,
          currentValue: '${char.weaponLevel}',
          targetValue: '${goal.targetWeaponLevel}',
          recommendation: 'Farm weapon ascension/exp materials.',
          confidence: RecommendationConfidence.high,
        ));
      }
    }

    // General diagnostics (no goals needed)
    if (char.weaponLevel < char.level - 20 && char.level > 40) {
      findings.add(DiagnosisFinding(
        type: DiagnosisType.weaponLevelLowVsCharacter,
        severity: DiagnosisSeverity.info,
        title: 'Weapon level is significantly below character level',
        explanation: 'Weapon Lv.${char.weaponLevel} vs Character Lv.${char.level}',
        characterId: characterId,
        currentValue: '${char.weaponLevel}',
        targetValue: '${char.level}',
        recommendation: 'Consider leveling the weapon to match the character level.',
        confidence: RecommendationConfidence.medium,
      ));
    }

    if (char.artifactCompletion == 0.0 && char.isOwned) {
      findings.add(DiagnosisFinding(
        type: DiagnosisType.artifactCompletionUnset,
        severity: DiagnosisSeverity.info,
        title: 'Artifact completion not set',
        explanation: 'Set artifact completion to track artifact progress.',
        characterId: characterId,
        recommendation: 'Set artifact completion in character details.',
        confidence: RecommendationConfidence.medium,
      ));
    }

    // Sort by severity then priority
    findings.sort((a, b) {
      const order = [DiagnosisSeverity.critical, DiagnosisSeverity.warning, DiagnosisSeverity.info];
      return order.indexOf(a.severity).compareTo(order.indexOf(b.severity));
    });

    return InvestmentDiagnosis(
      characterId: characterId,
      findings: findings,
      completeness: snapshot.completeness,
      missingData: missingData,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }
}
