import '../../domain/artifact_score.dart';
import '../../domain/artifact_score_weights.dart';
import '../../domain/models/master_models.dart';
import 'artifact_score_type_override_registry.dart';
import 'artifact_score_weight_repository.dart';

/// 画面表示と計算で共有する聖遺物スコア設定。
class ArtifactScoreSettings {
  const ArtifactScoreSettings({
    required this.scoreType,
    required this.weights,
    this.usesCustomWeights = false,
  });

  final ArtifactScoreType scoreType;
  final ArtifactStatWeights weights;
  final bool usesCustomWeights;
}

/// キャラクターとユーザー設定から、スコア基準と重みを一貫して解決する。
class ArtifactScoreResolver {
  const ArtifactScoreResolver(this._weightRepository);

  final ArtifactScoreWeightRepository _weightRepository;

  Future<ArtifactScoreSettings> resolve({
    required MasterCharacter character,
    ArtifactScoreType? userScoreType,
    bool userScoreTypeIsSet = false,
  }) async {
    final overrides = ArtifactScoreTypeOverrideRegistry.instance;
    await overrides.ensureLoaded();
    final nameOverrides = overrides.byName;

    if (userScoreTypeIsSet && userScoreType != null) {
      return ArtifactScoreSettings(
        scoreType: userScoreType,
        weights: scoreWeightsForType(userScoreType),
      );
    }

    final profile = await _weightRepository.findByCharacterId(character.id);
    if (profile != null) {
      final inferredType =
          inferArtifactScoreTypeFromWeights(profile.weights) ??
          resolveArtifactScoreType(character, nameOverrides: nameOverrides);
      return ArtifactScoreSettings(
        scoreType: inferredType,
        weights: profile.weights,
        usesCustomWeights:
            inferArtifactScoreTypeFromWeights(profile.weights) == null,
      );
    }

    final scoreType = resolveArtifactScoreType(
      character,
      nameOverrides: nameOverrides,
    );
    return ArtifactScoreSettings(
      scoreType: scoreType,
      weights: scoreWeightsForType(scoreType),
    );
  }
}
