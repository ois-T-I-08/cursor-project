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
          explanation: 'キャラレベルが育成目標に届いていません。',
          characterId: characterId,
          relatedGoalId: goal.id,
          currentValue: '${char.level}',
          targetValue: '${goal.targetLevel}',
          recommendation: '目標レベルまで優先して上げましょう。',
          confidence: RecommendationConfidence.high,
          completeness: snapshot.completeness,
        ));
      }

      // Talent below goal
      for (final talentCheck in [
        ('通常攻撃', goal.targetTalentNormal, char.talentNormal),
        ('元素スキル', goal.targetTalentSkill, char.talentSkill),
        ('元素爆発', goal.targetTalentBurst, char.talentBurst),
      ]) {
        final label = talentCheck.$1;
        final target = talentCheck.$2;
        final current = talentCheck.$3;
        if (target != null && current < target) {
          findings.add(DiagnosisFinding(
            type: DiagnosisType.talentBelowGoal,
            severity: DiagnosisSeverity.warning,
            title: '$label Lv.$current → Lv.$target',
            explanation: '天賦レベルが育成目標に届いていません。',
            characterId: characterId,
            relatedGoalId: goal.id,
            currentValue: '$current',
            targetValue: '$target',
            recommendation: '天賦素材を集めて目標まで上げましょう。',
            confidence: RecommendationConfidence.high,
          ));
        }
      }

      // Weapon below goal
      if (goal.targetWeaponLevel != null && char.weaponLevel < goal.targetWeaponLevel!) {
        findings.add(DiagnosisFinding(
          type: DiagnosisType.weaponBelowGoal,
          severity: DiagnosisSeverity.warning,
          title: '武器 Lv.${char.weaponLevel} → Lv.${goal.targetWeaponLevel}',
          explanation: '武器レベルが育成目標に届いていません。',
          characterId: characterId,
          relatedGoalId: goal.id,
          currentValue: '${char.weaponLevel}',
          targetValue: '${goal.targetWeaponLevel}',
          recommendation: '武器突破・強化素材を集めましょう。',
          confidence: RecommendationConfidence.high,
        ));
      }
    }

    // General diagnostics (no goals needed)
    if (char.weaponLevel < char.level - 20 && char.level > 40) {
      findings.add(DiagnosisFinding(
        type: DiagnosisType.weaponLevelLowVsCharacter,
        severity: DiagnosisSeverity.info,
        title: '武器レベルがキャラレベルより大きく遅れています',
        explanation: '武器 Lv.${char.weaponLevel} / キャラ Lv.${char.level}',
        characterId: characterId,
        currentValue: '${char.weaponLevel}',
        targetValue: '${char.level}',
        recommendation: '武器レベルをキャラに近づけましょう。',
        confidence: RecommendationConfidence.medium,
      ));
    }

    // Artifact completion — same metric as character detail 聖遺物完成度
    if (char.isOwned && !char.artifactCompletionAvailable) {
      findings.add(DiagnosisFinding(
        type: DiagnosisType.artifactCompletionUnset,
        severity: DiagnosisSeverity.info,
        title: '聖遺物データがありません',
        explanation: 'キャラ詳細の聖遺物完成度を参照するには、装備データを登録してください。',
        characterId: characterId,
        recommendation: 'キャラ詳細の聖遺物項目で装備を登録しましょう。',
        confidence: RecommendationConfidence.medium,
      ));
    } else if (char.artifactCompletionAvailable &&
        char.artifactCompletion < 0.8) {
      final pct = (char.artifactCompletion * 100).round();
      findings.add(DiagnosisFinding(
        type: DiagnosisType.artifactCompletionLow,
        severity: char.artifactCompletion < 0.5
            ? DiagnosisSeverity.warning
            : DiagnosisSeverity.info,
        title: '聖遺物完成度 $pct%',
        explanation: 'キャラ詳細と同じ完成度指標で 80% 未満です'
            '（部位の装備・レベル・メイン／サブステ・スコア寄与の平均）。',
        characterId: characterId,
        currentValue: '$pct',
        targetValue: '80',
        recommendation: '未装備部位の補完や強化で完成度を上げましょう。',
        confidence: RecommendationConfidence.high,
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
