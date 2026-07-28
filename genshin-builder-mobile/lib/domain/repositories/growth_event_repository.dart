import '../history/growth_event.dart';

abstract class GrowthEventRepository {
  Future<void> saveAll(List<GrowthEvent> events);
  Future<List<GrowthEvent>> getByUser(
    String userId, {
    int limit = 50,
    GrowthEventCursor? cursor,
  });
  Future<List<GrowthEvent>> getByCharacter(String userId, String characterId);
  Future<bool> existsByDedupKey(String dedupKey);
}
