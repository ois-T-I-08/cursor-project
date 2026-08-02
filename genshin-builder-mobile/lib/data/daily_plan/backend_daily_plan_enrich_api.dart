import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/planning/daily_plan.dart';
import '../../domain/planning/daily_plan_proposal.dart';
import '../../domain/planning/daily_plan_item_key.dart';
import 'daily_plan_proposal_codec.dart';

/// Fetches an optional server-side DeepSeek proposal for local candidates.
/// Fail-closed: callers retain their deterministic local plan on every error.
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
  static const _userAgent = 'genshin-builder-mobile/0.1 (daily-plan)';

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<DailyPlanProposal?> suggest({
    required DailyPlan plan,
    required int weekday,
    required String clientScope,
    bool force = false,
  }) async {
    if (plan.items.isEmpty) return null;
    final uri = _endpoint();
    if (uri == null) return null;
    final body = jsonEncode({
      'clientScope': clientScope,
      'date': formatLocalDate(plan.date),
      'timezone': _timezoneLabel(DateTime.now().timeZoneOffset),
      'weekday': weekday,
      'currentResin': plan.currentResin,
      'maxResin': plan.maxResin,
      'availableMinutes': plan.availableMinutes,
      'force': force,
      'candidates': [
        for (final item in plan.items.take(20))
          {
            'taskId': item.id,
            'type': item.type.name,
            'title': item.title,
            'characterIds': item.characterIds.take(8).toList(),
            'materialIds': item.materialIds.take(16).toList(),
            'currentLevel': item.currentLevel,
            'targetLevel': item.targetLevel,
            'estimatedResinCost': item.estimatedResinCost,
            'estimatedMinutes': item.estimatedMinutes,
            'availableToday': item.availableToday,
            'requiresResin': item.requiresResin,
            'bookmarked': item.bookmarked,
            'existingPriority': item.priority,
            'reasonFacts': item.reasons.take(8).toList(),
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

    if (response.statusCode != 200 ||
        response.bodyBytes.length > _maxResponseBytes) {
      return null;
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope.length != 2 ||
          !envelope.keys.every(const {'ok', 'data'}.contains) ||
          envelope['ok'] != true ||
          envelope['data'] == null) {
        return null;
      }
      return parseDailyPlanProposal(envelope['data'], plan: plan);
    } catch (_) {
      return null;
    }
  }

  String _timezoneLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final hours = absolute.inHours.toString().padLeft(2, '0');
    final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  Uri? _endpoint() {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        (base.scheme != 'https' && !_isLocalDevelopmentHttp(base))) {
      return null;
    }
    return base.resolve('/api/daily-plan/enrich');
  }
}

bool _isLocalDevelopmentHttp(Uri uri) =>
    uri.scheme == 'http' &&
    const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
