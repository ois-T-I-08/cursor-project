import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_template_replacement.dart';

void main() {
  test('育成準備度は編成適性と分離して計算する', () {
    const build = SimulationBuildSnapshot(
      characterId: '10000031',
      element: 'hydro',
      rarity: 4,
      isOwned: true,
      level: 80,
      ascension: 5,
      constellation: 2,
      talents: {'normal': 6, 'skill': 8, 'burst': 8},
      weapon: {'level': 80},
      artifacts: {'completed': true},
      inputQuality: SimulationInputQuality.exact,
    );
    final readiness = calculateBuildReadiness(build);
    expect(readiness, greaterThan(70));
    expect(calculateBuildReadiness(null), 0);
  });

  test('総合点の重みは差し替え可能で未所持でも適性は保持する', () {
    const candidate = ReplacementCandidate(
      characterId: '10000031',
      element: 'hydro',
      roles: ['sub_dps'],
      tags: ['off_field_dps'],
      compatibilityScore: 90,
      category: ReplacementCategory.optimal,
      confidence: 0.9,
      reasons: ['適合'],
      tradeoffs: [],
      requiredChanges: [],
      teamEvaluation: ReplacementTeamEvaluation(
        reactionViability: 90,
        damageBalance: 90,
        sustain: 60,
        energy: 80,
        fieldTimeBalance: 90,
      ),
      deterministicPenalty: 0,
      finalScore: 90,
    );
    final result = TeamReplacementResult(
      templateId: 'template-12345',
      replacedCharacterId: '10000052',
      generatedAt: DateTime.utc(2026, 7, 26),
      dataVersion: 'v1',
      isStale: false,
      source: 'deepseek',
      requiredFunctions: const [],
      preferredFunctions: const [],
      dependencies: const [],
      replacementRisks: const [],
      candidates: const [candidate],
    );
    final ranked = rankReplacementCandidates(
      result: result,
      builds: const [],
      weights: const ReplacementScoreWeights(suitability: 0.8, readiness: 0.2),
    );
    expect(ranked.single.isOwned, isFalse);
    expect(ranked.single.candidate.finalScore, 90);
    expect(ranked.single.overallScore, 72);
  });
}
