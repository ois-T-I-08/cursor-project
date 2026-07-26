import 'team_recommendation.dart';

enum ReplacementCategory { optimal, conditional, compromise, notRecommended }

class TeamTemplateMember {
  const TeamTemplateMember({
    required this.characterId,
    required this.role,
    required this.slotIndex,
  });

  final String characterId;
  final String role;
  final int slotIndex;
}

class PublishedTeamTemplate {
  const PublishedTeamTemplate({
    required this.id,
    required this.name,
    required this.archetype,
    required this.members,
    required this.source,
    required this.sourceUrl,
    required this.dataVersion,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String archetype;
  final List<TeamTemplateMember> members;
  final String source;
  final Uri? sourceUrl;
  final String dataVersion;
  final DateTime updatedAt;
}

class ReplacementTeamEvaluation {
  const ReplacementTeamEvaluation({
    required this.reactionViability,
    required this.damageBalance,
    required this.sustain,
    required this.energy,
    required this.fieldTimeBalance,
  });

  final double reactionViability;
  final double damageBalance;
  final double sustain;
  final double energy;
  final double fieldTimeBalance;
}

class ReplacementCandidate {
  const ReplacementCandidate({
    required this.characterId,
    required this.element,
    required this.roles,
    required this.tags,
    required this.compatibilityScore,
    required this.category,
    required this.confidence,
    required this.reasons,
    required this.tradeoffs,
    required this.requiredChanges,
    required this.teamEvaluation,
    required this.deterministicPenalty,
    required this.finalScore,
  });

  final String characterId;
  final String element;
  final List<String> roles;
  final List<String> tags;
  final double compatibilityScore;
  final ReplacementCategory category;
  final double confidence;
  final List<String> reasons;
  final List<String> tradeoffs;
  final List<String> requiredChanges;
  final ReplacementTeamEvaluation teamEvaluation;
  final int deterministicPenalty;
  final double finalScore;
}

class TeamReplacementResult {
  const TeamReplacementResult({
    required this.templateId,
    required this.replacedCharacterId,
    required this.generatedAt,
    required this.dataVersion,
    required this.isStale,
    required this.source,
    required this.requiredFunctions,
    required this.preferredFunctions,
    required this.dependencies,
    required this.replacementRisks,
    required this.candidates,
  });

  final String templateId;
  final String replacedCharacterId;
  final DateTime generatedAt;
  final String dataVersion;
  final bool isStale;
  final String source;
  final List<String> requiredFunctions;
  final List<String> preferredFunctions;
  final List<String> dependencies;
  final List<String> replacementRisks;
  final List<ReplacementCandidate> candidates;
}

class ReplacementScoreWeights {
  const ReplacementScoreWeights({this.suitability = 0.7, this.readiness = 0.3})
    : assert(suitability >= 0),
      assert(readiness >= 0),
      assert(suitability + readiness > 0);

  final double suitability;
  final double readiness;
}

class ReplacementCandidateDisplay {
  const ReplacementCandidateDisplay({
    required this.candidate,
    required this.isOwned,
    required this.readinessScore,
    required this.overallScore,
    required this.build,
  });

  final ReplacementCandidate candidate;
  final bool isOwned;
  final double readinessScore;
  final double overallScore;
  final SimulationBuildSnapshot? build;
}

class TeamReplacementDisplayResult {
  const TeamReplacementDisplayResult({
    required this.result,
    required this.candidates,
    this.readinessLimited = false,
  });

  final TeamReplacementResult result;
  final List<ReplacementCandidateDisplay> candidates;
  final bool readinessLimited;
}

List<ReplacementCandidateDisplay> rankReplacementCandidates({
  required TeamReplacementResult result,
  required List<SimulationBuildSnapshot> builds,
  ReplacementScoreWeights weights = const ReplacementScoreWeights(),
}) {
  final byCharacter = {for (final build in builds) build.characterId: build};
  final totalWeight = weights.suitability + weights.readiness;
  final ranked =
      result.candidates.map((candidate) {
        final build = byCharacter[candidate.characterId];
        final readiness = calculateBuildReadiness(build);
        final overall =
            (candidate.finalScore * weights.suitability +
                readiness * weights.readiness) /
            totalWeight;
        return ReplacementCandidateDisplay(
          candidate: candidate,
          isOwned: build?.isOwned ?? false,
          readinessScore: readiness,
          overallScore: overall,
          build: build,
        );
      }).toList();
  ranked.sort(
    (a, b) =>
        b.overallScore.compareTo(a.overallScore) != 0
            ? b.overallScore.compareTo(a.overallScore)
            : a.candidate.characterId.compareTo(b.candidate.characterId),
  );
  return ranked;
}

double calculateBuildReadiness(SimulationBuildSnapshot? build) {
  if (build == null || !build.isOwned) return 0;
  var score = 25.0;
  score += build.level.clamp(1, 90) / 90 * 20;
  score += build.ascension.clamp(0, 6) / 6 * 10;
  final talents = build.talents?.values.toList() ?? const <int>[];
  if (talents.isNotEmpty) {
    score +=
        talents.map((value) => value.clamp(1, 15)).reduce((a, b) => a + b) /
        talents.length /
        10 *
        15;
  }
  score += build.constellation.clamp(0, 6) / 6 * 5;
  if (build.weapon != null && build.weapon!.isNotEmpty) score += 15;
  if (build.artifacts != null && build.artifacts!.isNotEmpty) score += 10;
  return score.clamp(0, 100);
}
