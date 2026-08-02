import 'dart:convert';

import 'package:http/http.dart' as http;

import 'akasha_weapon_usage.dart';

/// Akasha System（https://akasha.cv）の公開ビルド API クライアント
class AkashaWeaponUsageApi {
  AkashaWeaponUsageApi({
    http.Client? client,
    this.baseUrl = 'https://akasha.cv/api',
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  static const _userAgent = 'genshin-builder-mobile/0.1 (weapon-usage)';

  /// 1 ページ分のビルドを取得する。
  ///
  /// [sort] は `_id` を推奨（critValue だと上位ビルドに偏る）。
  Future<List<dynamic>> fetchBuildsPage({
    required String characterId,
    int page = 1,
    int size = 50,
    String sort = '_id',
    int order = -1,
  }) async {
    final uri = Uri.parse('$baseUrl/builds').replace(
      queryParameters: {
        'sort': sort,
        'order': '$order',
        'size': '$size',
        'page': '$page',
        'filter': '[characterId]$characterId',
      },
    );
    final response = await _client
        .get(
          uri,
          headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('akasha builds error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('akasha builds: unexpected body');
    }
    final message = decoded['message'];
    if (message is String && message.contains('I want')) {
      throw Exception('akasha builds: invalid request');
    }
    final data = decoded['data'];
    if (data is! List) return const [];
    return data;
  }

  /// 複数ページを集計して使用率スナップショットを返す
  Future<WeaponUsageSnapshot> fetchUsageRates({
    required String characterId,
    int pages = 4,
    int pageSize = 50,
  }) async {
    final counts = <String, int>{};
    var sampleSize = 0;

    for (var page = 1; page <= pages; page++) {
      final builds = await fetchBuildsPage(
        characterId: characterId,
        page: page,
        size: pageSize,
      );
      if (builds.isEmpty) break;
      final pageCounts = countWeaponIdsFromBuilds(builds);
      for (final e in pageCounts.entries) {
        counts[e.key] = (counts[e.key] ?? 0) + e.value;
        sampleSize += e.value;
      }
    }

    return WeaponUsageSnapshot(
      characterId: characterId,
      rates: ratesFromCounts(counts),
      sampleSize: sampleSize,
      source: 'akasha.cv/api/builds',
      fetchedAt: DateTime.now(),
    );
  }

  void dispose() => _client.close();
}
