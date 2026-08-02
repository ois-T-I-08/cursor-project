import '../build_recommendations/build_recommendation.dart';

abstract class BuildRecommendationRepository {
  Future<CharacterBuildRecommendation?> fetchPublished(String characterId);
}
