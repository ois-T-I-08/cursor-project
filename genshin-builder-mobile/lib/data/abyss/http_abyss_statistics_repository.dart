import '../../domain/abyss/abyss_statistics.dart';
import '../../domain/repositories/abyss_statistics_repository.dart';
import 'backend_abyss_statistics_api.dart';

class HttpAbyssStatisticsRepository implements AbyssStatisticsRepository {
  const HttpAbyssStatisticsRepository(this._api);

  final BackendAbyssStatisticsApi _api;

  @override
  Future<AbyssStatistics> fetchLatest() => _api.fetchLatest();
}
