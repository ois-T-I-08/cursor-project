import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/gacha/gacha_banner_schedule.dart';
import 'asset_gacha_banner_history_source.dart';

/// リモート JSON からバナー履歴を取得（`--dart-define=GACHA_BANNER_HISTORY_URL=`）
class RemoteGachaBannerHistorySource implements GachaBannerHistorySource {
  RemoteGachaBannerHistorySource({
    required this.url,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String url;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<GachaBannerSchedule> load() async {
    if (url.isEmpty) {
      throw StateError('GACHA_BANNER_HISTORY_URL is empty');
    }
    final response = await _client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'gacha banner history remote error: ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return GachaBannerSchedule.fromJson(decoded);
  }
}
