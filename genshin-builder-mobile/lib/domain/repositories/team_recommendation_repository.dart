import '../team_recommendation/team_recommendation.dart';
import '../team_recommendation/team_template_replacement.dart';

abstract class TeamRecommendationRepository {
  Future<TeamSimulationJob> enqueue(TeamRecommendationRequest request);
  Future<TeamSimulationJob> getJob(String jobId);
}

abstract class TeamTemplateReplacementRepository {
  Future<List<PublishedTeamTemplate>> getTemplates();
  Future<TeamReplacementResult> getReplacement({
    required String templateId,
    required String characterId,
  });
}
