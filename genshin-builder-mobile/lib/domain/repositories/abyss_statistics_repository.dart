import '../abyss/abyss_statistics.dart';

abstract class AbyssStatisticsRepository {
  Future<AbyssStatistics> fetchLatest();
}
