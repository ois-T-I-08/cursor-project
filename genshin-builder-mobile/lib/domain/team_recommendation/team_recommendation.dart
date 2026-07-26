enum SimulationInputQuality { exact, partial, defaulted, unsupported }

enum TeamSimulationJobStatus { queued, running, completed, failed, expired }

class SimulationBuildSnapshot {
  const SimulationBuildSnapshot({
    required this.characterId,
    required this.element,
    required this.rarity,
    required this.isOwned,
    required this.level,
    required this.ascension,
    required this.constellation,
    this.talents,
    this.weapon,
    this.artifacts,
    required this.inputQuality,
    this.defaultedFields = const [],
  });

  final String characterId;
  final String element;
  final int rarity;
  final bool isOwned;
  final int level;
  final int ascension;
  final int constellation;
  final Map<String, int>? talents;
  final Map<String, Object>? weapon;
  final Map<String, Object>? artifacts;
  final SimulationInputQuality inputQuality;
  final List<String> defaultedFields;

  Map<String, Object?> toJson() => {
    'characterId': characterId,
    'element': element,
    'rarity': rarity,
    'isOwned': isOwned,
    'level': level,
    'ascension': ascension,
    'constellation': constellation,
    if (talents != null) 'talents': talents,
    if (weapon != null) 'weapon': weapon,
    if (artifacts != null) 'artifacts': artifacts,
    'inputQuality': inputQuality.name,
    'defaultedFields': defaultedFields,
  };
}

class TeamRecommendationRequest {
  const TeamRecommendationRequest({
    required this.attackerId,
    required this.half,
    required this.ownedOnly,
    required this.enemy,
    required this.preference,
    required this.characters,
  });
  final String attackerId;
  final String half;
  final bool ownedOnly;
  final String enemy;
  final String preference;
  final List<SimulationBuildSnapshot> characters;

  Map<String, Object?> toJson() => {
    'attackerId': attackerId,
    'mode': 'spiralAbyss',
    'half': half,
    'ownedOnly': ownedOnly,
    'enemy': enemy,
    'preference': preference,
    'characters': characters.map((value) => value.toJson()).toList(),
  };
}

class TeamRecommendation {
  const TeamRecommendation({
    required this.members,
    required this.score,
    required this.simulationStatus,
    required this.sourceTypes,
    required this.rotationConfidence,
    required this.observedByAza,
    required this.inputQuality,
    required this.reasons,
    required this.alternatives,
  });
  final List<String> members;
  final double score;
  final String simulationStatus;
  final List<String> sourceTypes;
  final String rotationConfidence;
  final bool observedByAza;
  final SimulationInputQuality inputQuality;
  final List<String> reasons;
  final Map<String, List<String>> alternatives;
}

class TeamRecommendationResult {
  const TeamRecommendationResult({
    required this.attackerId,
    required this.generatedAt,
    required this.engine,
    required this.recommendations,
    this.warning,
  });
  final String attackerId;
  final DateTime generatedAt;
  final String engine;
  final List<TeamRecommendation> recommendations;
  final String? warning;
}

class TeamSimulationJob {
  const TeamSimulationJob({
    required this.jobId,
    required this.status,
    this.result,
    this.errorCode,
  });
  final String jobId;
  final TeamSimulationJobStatus status;
  final TeamRecommendationResult? result;
  final String? errorCode;
}
