import '../../domain/artifact_score.dart';

/// specialProp と参照ステータスが一致しないキャラのスコア基準上書き。
class ArtifactScoreTypeOverride {
  const ArtifactScoreTypeOverride({
    required this.characterId,
    required this.name,
    required this.scoreType,
    this.note,
  });

  final String characterId;
  final String name;
  final ArtifactScoreType scoreType;
  final String? note;

  factory ArtifactScoreTypeOverride.fromJson(Map<String, dynamic> json) {
    final rawType = json['scoreType'] as String? ?? 'atk';
    final scoreType =
        artifactScoreTypeFromString(rawType) ?? ArtifactScoreType.atk;
    return ArtifactScoreTypeOverride(
      characterId: json['characterId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      scoreType: scoreType,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'name': name,
    'scoreType': artifactScoreTypeToStorage(scoreType),
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}
