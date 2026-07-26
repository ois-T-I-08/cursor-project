import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/build_recommendations/build_recommendation.dart';
import '../../domain/character_stats.dart';

class BackendBuildRecommendationApi {
  BackendBuildRecommendationApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  static const _maxResponseBytes = 512 * 1024;
  static const _userAgent =
      'genshin-builder-mobile/0.1 (build-recommendations-backend)';

  Future<CharacterBuildRecommendation?> fetchPublished(String characterId) async {
    final uri = _uri(characterId);
    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.timeout,
      );
    } on http.ClientException {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.networkError,
      );
    } catch (_) {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.networkError,
      );
    }

    if (response.bodyBytes.length > _maxResponseBytes) {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.invalidResponse,
      );
    }

    final decoded = _decodeObject(response.bodyBytes);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200 || decoded['ok'] != true) {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.invalidResponse,
      );
    }
    return parseBuildRecommendation(_object(decoded['data']));
  }

  Uri _uri(String characterId) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.notConfigured,
      );
    }
    final Uri base;
    try {
      base = Uri.parse(trimmed);
    } on FormatException {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.notConfigured,
      );
    }
    if (!base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'https' && !_isLocalDevelopmentHttp(base)) ||
        base.userInfo.isNotEmpty) {
      throw const BuildRecommendationException(
        BuildRecommendationFailure.notConfigured,
      );
    }
    final encoded = Uri.encodeComponent(characterId);
    return base.resolve('/api/build-recommendations/$encoded');
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

bool _isLocalDevelopmentHttp(Uri uri) {
  if (uri.scheme != 'http') return false;
  return const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
}

CharacterBuildRecommendation parseBuildRecommendation(Map<String, Object?> json) {
  final context = _object(json['context']);
  final targets = <BuildStatTarget>[];
  for (final item in _list(json['targets'], maxLength: 20)) {
    final map = _object(item);
    final stat = parseGuideStatKey(_string(map['stat']));
    if (stat == null) continue;
    targets.add(
      BuildStatTarget(
        stat: stat,
        recommended: _optionalDouble(map['recommended']),
        min: _optionalDouble(map['min']),
        max: _optionalDouble(map['max']),
        unit: map['unit'] is String ? map['unit'] as String : null,
      ),
    );
  }

  final priority = <StatKey>[];
  for (final item in _list(json['substatPriority'], maxLength: 10)) {
    final raw = item is String ? item : null;
    if (raw == null) continue;
    final key = parseGuideStatKey(raw);
    if (key != null) priority.add(key);
  }

  final sources = <BuildRecommendationSource>[];
  for (final item in _list(json['sources'], maxLength: 20)) {
    final map = _object(item);
    sources.add(
      BuildRecommendationSource(
        videoId: _string(map['videoId']),
        title: _string(map['title']),
        channelTitle: _string(map['channelTitle']),
        sourceUrl: _string(map['sourceUrl']),
        publishedAt: _optionalDate(map['publishedAt']),
      ),
    );
  }

  final evidence = <BuildRecommendationEvidence>[];
  for (final item in _list(json['evidence'], maxLength: 40)) {
    final map = _object(item);
    evidence.add(
      BuildRecommendationEvidence(
        fieldPath: _string(map['fieldPath']),
        exactVisibleText: _string(
          map['exactVisibleText'] ?? map['snippet'],
        ),
        videoId: _string(map['videoId']),
        startSeconds:
            _optionalDouble(map['startSeconds']) ??
            ((_optionalInt(map['startMs']) ?? 0) / 1000),
        endSeconds:
            _optionalDouble(map['endSeconds']) ??
            ((_optionalInt(map['endMs']) ?? 0) / 1000),
      ),
    );
  }

  final caveats = <String>[];
  for (final item in _list(json['caveats'], maxLength: 10)) {
    if (item is String && item.trim().isNotEmpty) caveats.add(item.trim());
  }

  final originRaw = _string(json['origin']);
  final origin = originRaw == 'merged'
      ? BuildRecommendationOrigin.merged
      : BuildRecommendationOrigin.singleVideo;

  return CharacterBuildRecommendation(
    characterId: _string(json['characterId']),
    label: _string(json['label'], fallback: '動画内推奨目安'),
    origin: origin,
    overallConfidence: _optionalDouble(json['overallConfidence']) ?? 0,
    targets: targets,
    substatPriority: priority,
    caveats: caveats,
    sources: sources,
    evidence: evidence,
    lastVerifiedAt: _optionalDate(json['lastVerifiedAt']),
    publishedAt: _optionalDate(json['publishedAt']),
    role: context['role'] is String ? context['role'] as String : null,
    teamArchetype: context['teamArchetype'] is String
        ? context['teamArchetype'] as String
        : null,
  );
}

Map<String, Object?> _decodeObject(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }
  } catch (_) {}
  throw const BuildRecommendationException(
    BuildRecommendationFailure.invalidResponse,
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, dynamic>) return value.cast<String, Object?>();
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return const {};
}

List<Object?> _list(Object? value, {required int maxLength}) {
  if (value is! List) return const [];
  return value.take(maxLength).cast<Object?>().toList();
}

String _string(Object? value, {String fallback = ''}) {
  if (value is! String) return fallback;
  return value.length > 500 ? value.substring(0, 500) : value;
}

double? _optionalDouble(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.round();
  return null;
}

DateTime? _optionalDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
