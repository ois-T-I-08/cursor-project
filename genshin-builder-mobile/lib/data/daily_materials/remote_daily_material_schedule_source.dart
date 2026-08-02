import 'package:http/http.dart' as http;

import '../../domain/daily_materials/daily_material_models.dart';
import '../config/config_load_log.dart';
import '../config/config_validators.dart';
import '../config/remote_json_fetch.dart';
import 'daily_material_schedule_repository.dart';

const _configKind = 'daily_material_schedule';

/// リモート JSON から曜日スケジュールを取得（`--dart-define=DAILY_MATERIAL_SCHEDULE_URL=`）
class RemoteDailyMaterialScheduleSource implements DailyMaterialScheduleSource {
  RemoteDailyMaterialScheduleSource({
    required this.url,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String url;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<DailyMaterialSchedule> load() async {
    if (url.isEmpty) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
    final decoded = await fetchRemoteJsonMap(
      client: _client,
      url: url,
      kind: _configKind,
      timeout: timeout,
      maxBytes: kRemoteJsonMaxBytesDailyMaterialSchedule,
    );
    try {
      validateDailyMaterialScheduleJson(decoded);
    } on FormatException catch (e) {
      throw configLoadFromFormatException(kind: _configKind, error: e);
    }
    try {
      return DailyMaterialSchedule.fromJson(decoded);
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
  }
}
