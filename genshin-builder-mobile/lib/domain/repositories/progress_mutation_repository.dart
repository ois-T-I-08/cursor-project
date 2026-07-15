import '../history/growth_event.dart';
import '../models/master_models.dart';

abstract class ProgressMutationRepository {
  Future<List<GrowthEvent>> saveWithEvents({
    required UserProgress progress,
    required String userId,
    UserProgress? before,
    String source = 'localManual',
  });
}
