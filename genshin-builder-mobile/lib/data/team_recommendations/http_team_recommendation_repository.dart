import '../../domain/repositories/team_recommendation_repository.dart';
import '../../domain/team_recommendation/team_recommendation.dart';
import '../../domain/team_recommendation/team_template_replacement.dart';
import 'backend_team_recommendation_api.dart';

class HttpTeamRecommendationRepository
    implements TeamRecommendationRepository, TeamTemplateReplacementRepository {
  const HttpTeamRecommendationRepository(this.api);
  final BackendTeamRecommendationApi api;
  @override
  Future<TeamSimulationJob> enqueue(TeamRecommendationRequest request) =>
      api.enqueue(request);
  @override
  Future<TeamSimulationJob> getJob(String jobId) => api.getJob(jobId);
  @override
  Future<List<PublishedTeamTemplate>> getTemplates() => api.getTemplates();
  @override
  Future<TeamReplacementResult> getReplacement({
    required String templateId,
    required String characterId,
  }) => api.getReplacement(templateId: templateId, characterId: characterId);
}
