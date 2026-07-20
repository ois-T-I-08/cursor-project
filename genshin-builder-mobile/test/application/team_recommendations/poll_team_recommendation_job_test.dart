import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/team_recommendations/poll_team_recommendation_job.dart';
import 'package:genshin_builder_mobile/domain/repositories/team_recommendation_repository.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';

void main() {
  const id = '123e4567-e89b-42d3-a456-426614174000';
  test('polls queued and running job until completed', () async {
    final repository = _FakeRepository([
      const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.running,
      ),
      const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.completed,
      ),
    ]);
    final states = <TeamSimulationJobStatus>[];
    final result = await pollTeamRecommendationJob(
      repository: repository,
      initial: const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.queued,
      ),
      interval: Duration.zero,
      delay: (_) async {},
      onProgress: (job) => states.add(job.status),
    );
    expect(result.status, TeamSimulationJobStatus.completed);
    expect(states, [
      TeamSimulationJobStatus.running,
      TeamSimulationJobStatus.completed,
    ]);
    expect(repository.calls, 2);
  });

  test('returns failed job and allows caller retry', () async {
    final repository = _FakeRepository([
      const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.failed,
        errorCode: 'simulationFailed',
      ),
    ]);
    final result = await pollTeamRecommendationJob(
      repository: repository,
      initial: const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.queued,
      ),
      delay: (_) async {},
    );
    expect(result.status, TeamSimulationJobStatus.failed);
    expect(result.errorCode, 'simulationFailed');
  });

  test('does not publish an in-flight response after cancellation', () async {
    var cancelled = false;
    final repository = _FakeRepository(const [
      TeamSimulationJob(jobId: id, status: TeamSimulationJobStatus.running),
    ], onGet: () => cancelled = true);
    var progressCalls = 0;
    final result = await pollTeamRecommendationJob(
      repository: repository,
      initial: const TeamSimulationJob(
        jobId: id,
        status: TeamSimulationJobStatus.queued,
      ),
      interval: Duration.zero,
      delay: (_) async {},
      onProgress: (_) => progressCalls += 1,
      isCancelled: () => cancelled,
    );
    expect(result.status, TeamSimulationJobStatus.queued);
    expect(repository.calls, 1);
    expect(progressCalls, 0);
  });

  test('stops after the finite polling limit', () async {
    final repository = _FakeRepository(
      List.filled(
        2,
        const TeamSimulationJob(
          jobId: id,
          status: TeamSimulationJobStatus.running,
        ),
      ),
    );
    await expectLater(
      pollTeamRecommendationJob(
        repository: repository,
        initial: const TeamSimulationJob(
          jobId: id,
          status: TeamSimulationJobStatus.queued,
        ),
        maxAttempts: 2,
        interval: Duration.zero,
        delay: (_) async {},
      ),
      throwsA(isA<TeamRecommendationPollingException>()),
    );
    expect(repository.calls, 2);
  });
}

class _FakeRepository implements TeamRecommendationRepository {
  _FakeRepository(this.jobs, {this.onGet});
  final List<TeamSimulationJob> jobs;
  final void Function()? onGet;
  int calls = 0;
  @override
  Future<TeamSimulationJob> enqueue(TeamRecommendationRequest request) async =>
      jobs.first;
  @override
  Future<TeamSimulationJob> getJob(String jobId) async {
    onGet?.call();
    return jobs[calls++];
  }
}
