import '../../domain/account/account_snapshot.dart';
import '../../domain/account/account_health_report.dart';
import '../../domain/recommendation/recommendation.dart';

/// Generates an [AccountHealthReport] from an [AccountSnapshot].
///
/// No character roles, synergies, or external stats are used.
/// This is a pure data-driven health assessment of the user's account.
///
/// Note: Data Completeness is NOT included in the total score.
/// It is stored separately as [AccountHealthReport.dataCoverage].
class GenerateAccountHealthReportUseCase {
  const GenerateAccountHealthReportUseCase();

  static const ruleVersion = '2';

  AccountHealthReport call({
    required AccountSnapshot snapshot,
    DateTime? generatedAt,
  }) {
    final chars = snapshot.characters;
    final owned = chars.where((c) => c.isOwned).toList();
    final totalOwned = owned.length;
    final categories = <AccountHealthCategory>[];
    final hasInventory = snapshot.materialInventory.isNotEmpty;

    // 1. Character level investment
    double levelScore = 0;
    bool levelEval = false;
    int leveled = 0;
    if (totalOwned > 0) {
      leveled = owned.where((c) => c.level >= 80).length;
      levelScore = (leveled / totalOwned * 100).clamp(0.0, 100.0);
      levelEval = true;
    }
    categories.add(AccountHealthCategory(
      name: 'キャラレベル',
      score: levelScore,
      weight: 1.5,
      evaluated: levelEval,
      evidenceCount: totalOwned,
      reasons: levelEval
          ? ['所持キャラ $totalOwned 体中 $leveled 体が Lv.80以上']
          : ['所持キャラがありません'],
      improvementHints: levelScore < 50 && levelEval
          ? ['主要なキャラを Lv.80以上まで育てましょう']
          : [],
      missingData: totalOwned == 0 ? [MissingData.materialInventory] : [],
    ));

    // 2. Talent level investment
    double talentScore = 0;
    bool talentEval = false;
    int talentChars = 0;
    if (totalOwned > 0) {
      talentChars = owned.where((c) {
        var high = 0;
        for (final t in [c.talentNormal, c.talentSkill, c.talentBurst]) {
          if (t >= 6) high++;
        }
        return high >= 2;
      }).length;
      talentScore = (talentChars / totalOwned * 100).clamp(0.0, 100.0);
      talentEval = true;
    }
    categories.add(AccountHealthCategory(
      name: '天賦レベル',
      score: talentScore,
      weight: 1.2,
      evaluated: talentEval,
      evidenceCount: talentChars,
      reasons: talentEval
          ? ['$talentChars 体が天賦 Lv.6以上を2つ以上持っています']
          : ['所持キャラがありません'],
      improvementHints: talentScore < 40 && talentEval
          ? ['メインキャラの主要天賦を上げましょう']
          : [],
    ));

    // 3. Weapon level investment
    double weaponScore = 0;
    bool weaponEval = false;
    int weaponChars = 0;
    if (totalOwned > 0) {
      weaponChars = owned.where((c) => c.weaponLevel >= 80).length;
      weaponScore = (weaponChars / totalOwned * 100).clamp(0.0, 100.0);
      weaponEval = true;
    }
    categories.add(AccountHealthCategory(
      name: '武器レベル',
      score: weaponScore,
      weight: 1.0,
      evaluated: weaponEval,
      evidenceCount: weaponChars,
      reasons: weaponEval
          ? ['$weaponChars 体の武器が Lv.80以上です']
          : ['所持キャラがありません'],
    ));

    // 4. Artifact completion — only evaluate if artifact data is available
    final artifactAvailable = owned.any((c) => c.artifactCompletionAvailable);
    double artifactScore = 0;
    int artifactChars = 0;
    if (artifactAvailable && totalOwned > 0) {
      artifactChars = owned.where((c) => c.artifactCompletionAvailable && c.artifactCompletion >= 0.8).length;
      artifactScore = (artifactChars / totalOwned * 100).clamp(0.0, 100.0);
    }
    categories.add(AccountHealthCategory(
      name: '聖遺物完成度',
      score: artifactScore,
      weight: 0.8,
      evaluated: artifactAvailable,
      evidenceCount: artifactChars,
      reasons: artifactAvailable
          ? ['$artifactChars 体の聖遺物完成度（キャラ詳細と同じ指標）が 80% 以上です']
          : ['聖遺物データがありません'],
      missingData: !artifactAvailable ? [MissingData.materialInventory] : [],
      improvementHints: !artifactAvailable
          ? ['キャラ詳細の聖遺物項目で装備を登録すると完成度を評価できます']
          : [],
    ));

    // 5. Growth goal completion — evaluated only when goals exist
    final totalGoals = snapshot.activeGoals.length;
    final goalEval = totalGoals > 0;
    final goalScore = goalEval ? 50.0 : 0.0;
    categories.add(AccountHealthCategory(
      name: '育成目標',
      score: goalScore,
      weight: 0.5,
      evaluated: goalEval,
      evidenceCount: totalGoals,
      reasons: goalEval
          ? ['アクティブな育成目標が $totalGoals 件あります']
          : ['育成目標が未設定のため評価できません'],
      improvementHints: !goalEval ? ['育成目標を設定して優先順位を決めましょう'] : [],
    ));

    // Calculate weighted total from evaluated categories only
    double totalWeight = 0;
    double weightedSum = 0;
    for (final cat in categories) {
      if (cat.evaluated) {
        weightedSum += cat.normalizedScore * cat.weight;
        totalWeight += cat.weight;
      }
    }
    final effectiveScore = totalWeight > 0 ? (weightedSum / totalWeight).clamp(0.0, 100.0) : null;

    // Strengths & improvements from evaluated categories only
    final strengths = categories.where((c) => c.evaluated && c.normalizedScore >= 70).map((c) => c.name).toList();
    final improvements = categories.where((c) => c.evaluated && c.normalizedScore < 40).map((c) => c.name).toList();

    // Data coverage (separate from health score)
    final dataCoverage = snapshot.completeness == DataCompleteness.complete
        ? '高'
        : snapshot.completeness == DataCompleteness.partial
            ? '中'
            : snapshot.completeness == DataCompleteness.minimal
                ? '低'
                : '不明';

    return AccountHealthReport(
      totalScore: effectiveScore,
      rating: effectiveScore != null ? AccountHealthReport.scoreToRating(effectiveScore) : HealthRating.unknown,
      categories: categories,
      strengths: strengths,
      improvementCandidates: improvements,
      dataCoverage: dataCoverage,
      confidence: hasInventory ? RecommendationConfidence.medium : RecommendationConfidence.low,
      completeness: snapshot.completeness,
      missingData: snapshot.missingData,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }
}
