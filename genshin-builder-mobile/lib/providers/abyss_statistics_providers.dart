import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/abyss/load_abyss_statistics_use_case.dart';
import '../data/abyss/backend_abyss_statistics_api.dart';
import '../data/abyss/http_abyss_statistics_repository.dart';
import '../domain/abyss/abyss_statistics.dart';
import '../domain/repositories/abyss_statistics_repository.dart';
import 'app_providers.dart';
import 'character_detail_providers.dart';

final backendAbyssStatisticsApiProvider = Provider<BackendAbyssStatisticsApi>((
  ref,
) {
  const baseUrl = String.fromEnvironment(
    'GENSHIN_BUILDER_API_BASE_URL',
    defaultValue: '',
  );
  final api = BackendAbyssStatisticsApi(baseUrl: baseUrl);
  ref.onDispose(api.dispose);
  return api;
});

final abyssStatisticsRepositoryProvider = Provider<AbyssStatisticsRepository>((
  ref,
) {
  return HttpAbyssStatisticsRepository(
    ref.watch(backendAbyssStatisticsApiProvider),
  );
});

final loadAbyssStatisticsUseCaseProvider =
    FutureProvider<LoadAbyssStatisticsUseCase>((ref) async {
      final characterRepository = await ref.watch(
        characterRepositoryProvider.future,
      );
      final amberDetail = ref.watch(amberDetailRepositoryProvider);
      return LoadAbyssStatisticsUseCase(
        statisticsRepository: ref.watch(abyssStatisticsRepositoryProvider),
        characterRepository: characterRepository,
        artifactSetNames: () async {
          final sets = await amberDetail.getArtifactSets();
          return {for (final set in sets) set.id: set.name};
        },
      );
    });

final abyssStatisticsProvider = FutureProvider<AbyssStatistics>((ref) async {
  final useCase = await ref.watch(loadAbyssStatisticsUseCaseProvider.future);
  return useCase.execute();
});
