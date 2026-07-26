import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/build_recommendations/backend_build_recommendation_api.dart';
import '../data/build_recommendations/http_build_recommendation_repository.dart';
import '../domain/build_recommendations/build_recommendation.dart';
import '../domain/repositories/build_recommendation_repository.dart';

final backendBuildRecommendationApiProvider =
    Provider<BackendBuildRecommendationApi>((ref) {
      const baseUrl = String.fromEnvironment(
        'GENSHIN_BUILDER_API_BASE_URL',
        defaultValue: '',
      );
      final api = BackendBuildRecommendationApi(baseUrl: baseUrl);
      ref.onDispose(api.dispose);
      return api;
    });

final buildRecommendationRepositoryProvider =
    Provider<BuildRecommendationRepository>((ref) {
      return HttpBuildRecommendationRepository(
        ref.watch(backendBuildRecommendationApiProvider),
      );
    });

final buildRecommendationProvider =
    FutureProvider.family<CharacterBuildRecommendation?, String>((
      ref,
      characterId,
    ) async {
      final repo = ref.watch(buildRecommendationRepositoryProvider);
      return repo.fetchPublished(characterId);
    });
