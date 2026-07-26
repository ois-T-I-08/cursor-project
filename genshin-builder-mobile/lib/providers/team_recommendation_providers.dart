import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/team_recommendations/normalize_simulation_builds.dart';
import '../application/team_recommendations/poll_team_recommendation_job.dart';
import '../data/team_recommendations/backend_team_recommendation_api.dart';
import '../data/team_recommendations/http_team_recommendation_repository.dart';
import '../data/hoyolab/models/game_record.dart';
import '../domain/repositories/team_recommendation_repository.dart';
import '../domain/team_recommendation/team_recommendation.dart';
import '../domain/team_recommendation/team_template_replacement.dart';
import 'app_providers.dart';
import 'hoyolab_game_providers.dart';

final backendTeamRecommendationApiProvider =
    Provider<BackendTeamRecommendationApi>((ref) {
      const baseUrl = String.fromEnvironment(
        'GENSHIN_BUILDER_API_BASE_URL',
        defaultValue: '',
      );
      final api = BackendTeamRecommendationApi(baseUrl: baseUrl);
      ref.onDispose(api.dispose);
      return api;
    });

final teamRecommendationRepositoryProvider =
    Provider<TeamRecommendationRepository>((ref) {
      return HttpTeamRecommendationRepository(
        ref.watch(backendTeamRecommendationApiProvider),
      );
    });

final teamTemplateReplacementRepositoryProvider =
    Provider<TeamTemplateReplacementRepository>((ref) {
      return HttpTeamRecommendationRepository(
        ref.watch(backendTeamRecommendationApiProvider),
      );
    });

final teamTemplatesProvider =
    FutureProvider.autoDispose<List<PublishedTeamTemplate>>((ref) {
      return ref
          .watch(teamTemplateReplacementRepositoryProvider)
          .getTemplates();
    });

final teamReplacementScoreWeightsProvider = Provider<ReplacementScoreWeights>((
  ref,
) {
  return const ReplacementScoreWeights();
});

class TeamReplacementKey {
  const TeamReplacementKey(this.templateId, this.characterId);
  final String templateId;
  final String characterId;

  @override
  bool operator ==(Object other) =>
      other is TeamReplacementKey &&
      other.templateId == templateId &&
      other.characterId == characterId;

  @override
  int get hashCode => Object.hash(templateId, characterId);
}

final teamReplacementDisplayProvider = FutureProvider.autoDispose
    .family<TeamReplacementDisplayResult, TeamReplacementKey>((ref, key) async {
      final repository = ref.watch(teamTemplateReplacementRepositoryProvider);
      final result = await repository.getReplacement(
        templateId: key.templateId,
        characterId: key.characterId,
      );
      final characters = await ref.read(charactersProvider.future);
      var builds = const <String, HoyolabCharacterBuild>{};
      var readinessLimited = false;
      try {
        final gameRepository = await ref.read(
          hoyolabGameDataRepositoryProvider.future,
        );
        builds = await gameRepository.fetchOwnedCharacterBuilds();
      } catch (_) {
        // 保存済み候補の表示は維持し、HoYoLAB未接続時はローカル育成だけで準備度を出す。
        readinessLimited = true;
      }
      final userId = await ref.read(localUserIdProvider.future);
      final progressRepository = await ref.read(
        progressRepositoryProvider.future,
      );
      final progress = await progressRepository.getAll(userId);
      final snapshots = normalizeSimulationBuilds(
        characters: characters,
        hoyolabBuilds: builds,
        localProgress: {for (final value in progress) value.characterId: value},
      );
      return TeamReplacementDisplayResult(
        result: result,
        readinessLimited: readinessLimited,
        candidates: rankReplacementCandidates(
          result: result,
          builds: snapshots,
          weights: ref.read(teamReplacementScoreWeightsProvider),
        ),
      );
    });

class TeamRecommendationOptions {
  const TeamRecommendationOptions({
    this.half = 'upper',
    this.ownedOnly = true,
    this.enemy = 'single',
    this.preference = 'damage',
  });
  final String half;
  final bool ownedOnly;
  final String enemy;
  final String preference;
}

final teamRecommendationControllerProvider = StateNotifierProvider.autoDispose
    .family<
      TeamRecommendationController,
      AsyncValue<TeamSimulationJob?>,
      String
    >((ref, attackerId) {
      return TeamRecommendationController(ref, attackerId);
    });

class TeamRecommendationController
    extends StateNotifier<AsyncValue<TeamSimulationJob?>> {
  TeamRecommendationController(this.ref, this.attackerId)
    : super(const AsyncValue.data(null));
  final Ref ref;
  final String attackerId;
  TeamRecommendationOptions _lastOptions = const TeamRecommendationOptions();
  bool _cancelled = false;
  int _runId = 0;

  Future<void> start(TeamRecommendationOptions options) async {
    if (_cancelled) return;
    final runId = ++_runId;
    bool isActive() => !_cancelled && _runId == runId;
    _lastOptions = options;
    state = const AsyncValue.loading();
    try {
      final characters = await ref.read(charactersProvider.future);
      if (!isActive()) return;
      final gameRepository = await ref.read(
        hoyolabGameDataRepositoryProvider.future,
      );
      if (!isActive()) return;
      final builds = await gameRepository.fetchOwnedCharacterBuilds();
      if (!isActive()) return;
      final userId = await ref.read(localUserIdProvider.future);
      if (!isActive()) return;
      final progressRepository = await ref.read(
        progressRepositoryProvider.future,
      );
      if (!isActive()) return;
      final progress = await progressRepository.getAll(userId);
      if (!isActive()) return;
      final snapshots = normalizeSimulationBuilds(
        characters: characters,
        hoyolabBuilds: builds,
        localProgress: {for (final value in progress) value.characterId: value},
      );
      if (!snapshots.any((value) => value.characterId == attackerId)) {
        throw const TeamRecommendationApiException('attackerUnavailable');
      }
      final repository = ref.read(teamRecommendationRepositoryProvider);
      var job = await repository.enqueue(
        TeamRecommendationRequest(
          attackerId: attackerId,
          half: options.half,
          ownedOnly: options.ownedOnly,
          enemy: options.enemy,
          preference: options.preference,
          characters: snapshots,
        ),
      );
      if (!isActive()) return;
      state = AsyncValue.data(job);
      job = await pollTeamRecommendationJob(
        repository: repository,
        initial: job,
        onProgress: (next) {
          if (isActive()) state = AsyncValue.data(next);
        },
        isCancelled: () => !isActive(),
      );
      if (isActive()) state = AsyncValue.data(job);
    } catch (error, stackTrace) {
      if (isActive()) state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> retry() => start(_lastOptions);

  @override
  void dispose() {
    _cancelled = true;
    _runId += 1;
    super.dispose();
  }
}
