import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/planning/apply_daily_plan_enrichment.dart';
import '../../domain/planning/daily_plan.dart';

/// Optional DeepSeek reorder/reason enrich for a local rule-based [DailyPlan].
/// Fail-closed: callers should keep the local plan on any error.
class BackendDailyPlanEnrichApi {
  BackendDailyPlanEnrichApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  static const _maxResponseBytes = 128 * 1024;
  static const _userAgent = 'genshin-builder-mobile/0.1 (daily-plan-enrich)';

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<DailyPlanEnrichment?> enrich({
    required DailyPlan plan,
    required int weekday,
  }) async {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty || plan.items.isEmpty) return null;

    final uri = Uri.parse('$trimmed/api/daily-plan/enrich');
    final body = jsonEncode({
      'weekday': weekday,
      'currentResin': plan.currentResin,
      'maxResin': plan.maxResin,
      'items': [
        for (final item in plan.items.take(12))
          {
            'id': item.id,
            'type': item.type.name,
            'title': item.title,
            'priority': item.priority,
            'reasons': item.reasons,
            'characterIds': item.characterIds,
            'materialIds': item.materialIds,
            if (item.estimatedResinCost != null)
              'estimatedResinCost': item.estimatedResinCost,
          },
      ],
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } catch (_) {
      return null;
    }

    if (response.statusCode != 200) return null;
    if (response.bodyBytes.length > _maxResponseBytes) return null;

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['ok'] != true) return null;
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;

      final orderedRaw = data['orderedItemIds'];
      if (orderedRaw is! List) return null;
      final orderedItemIds =
          orderedRaw.map((e) => '$e').where((e) => e.isNotEmpty).toList();

      final reasonsRaw = data['reasonsByItemId'];
      final reasonsByItemId = <String, List<String>>{};
      if (reasonsRaw is Map) {
        for (final entry in reasonsRaw.entries) {
          final key = '${entry.key}';
          final value = entry.value;
          if (value is! List) continue;
          reasonsByItemId[key] =
              value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).take(4).toList();
        }
      }

      return DailyPlanEnrichment(
        orderedItemIds: orderedItemIds,
        reasonsByItemId: reasonsByItemId,
        enriched: data['enriched'] == true,
        model: data['model'] is String ? data['model'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }
}
