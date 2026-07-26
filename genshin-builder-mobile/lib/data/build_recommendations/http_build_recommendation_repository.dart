import '../../domain/build_recommendations/build_recommendation.dart';
import '../../domain/repositories/build_recommendation_repository.dart';
import 'backend_build_recommendation_api.dart';

/// Remote-first repository with last-good in-memory cache (per process).
class HttpBuildRecommendationRepository implements BuildRecommendationRepository {
  HttpBuildRecommendationRepository(this._api);

  final BackendBuildRecommendationApi _api;
  final Map<String, CharacterBuildRecommendation> _cache = {};

  @override
  Future<CharacterBuildRecommendation?> fetchPublished(String characterId) async {
    try {
      final result = await _api.fetchPublished(characterId);
      if (result != null) {
        _cache[characterId] = result;
      }
      return result ?? _cache[characterId];
    } on BuildRecommendationException catch (error) {
      final cached = _cache[characterId];
      if (cached != null &&
          error.failure != BuildRecommendationFailure.notConfigured) {
        return cached;
      }
      rethrow;
    }
  }
}
