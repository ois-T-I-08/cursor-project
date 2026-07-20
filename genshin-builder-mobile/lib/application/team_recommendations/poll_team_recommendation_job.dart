import '../../domain/repositories/team_recommendation_repository.dart';
import '../../domain/team_recommendation/team_recommendation.dart';

Future<TeamSimulationJob> pollTeamRecommendationJob({
  required TeamRecommendationRepository repository,
  required TeamSimulationJob initial,
  int maxAttempts = 180,
  Duration interval = const Duration(seconds: 2),
  Future<void> Function(Duration) delay = Future<void>.delayed,
  void Function(TeamSimulationJob job)? onProgress,
  bool Function()? isCancelled,
}) async {
  var job = initial;
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    if (_terminal(job.status) || (isCancelled?.call() ?? false)) return job;
    await delay(interval);
    if (isCancelled?.call() ?? false) return job;
    final next = await repository.getJob(job.jobId);
    if (isCancelled?.call() ?? false) return job;
    job = next;
    onProgress?.call(job);
  }
  throw const TeamRecommendationPollingException();
}

bool _terminal(TeamSimulationJobStatus status) =>
    status == TeamSimulationJobStatus.completed ||
    status == TeamSimulationJobStatus.failed ||
    status == TeamSimulationJobStatus.expired;

class TeamRecommendationPollingException implements Exception {
  const TeamRecommendationPollingException();
}
