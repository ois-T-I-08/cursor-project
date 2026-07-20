import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/team_recommendation/team_recommendation.dart';

class TeamRecommendationApiException implements Exception {
  const TeamRecommendationApiException(this.code);
  final String code;
}

class BackendTeamRecommendationApi {
  BackendTeamRecommendationApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  static const _maxResponseBytes = 2 * 1024 * 1024;

  Future<TeamSimulationJob> enqueue(TeamRecommendationRequest request) async {
    return _send(
      () => _client.post(
        _uri('/api/team-recommendations'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'genshin-builder-mobile/0.1 (team-recommendations)',
        },
        body: jsonEncode(request.toJson()),
      ),
    );
  }

  Future<TeamSimulationJob> getJob(String jobId) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(jobId)) {
      throw const TeamRecommendationApiException('invalidJobId');
    }
    return _send(
      () => _client.get(
        _uri('/api/team-recommendations/jobs/$jobId'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'genshin-builder-mobile/0.1 (team-recommendations)',
        },
      ),
    );
  }

  Future<TeamSimulationJob> _send(Future<http.Response> Function() call) async {
    late http.Response response;
    try {
      response = await call().timeout(timeout);
    } on TimeoutException {
      throw const TeamRecommendationApiException('timeout');
    } on http.ClientException {
      throw const TeamRecommendationApiException('networkError');
    }
    if (response.bodyBytes.length > _maxResponseBytes) {
      throw const TeamRecommendationApiException('invalidResponse');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: false),
      );
    } catch (_) {
      throw const TeamRecommendationApiException('invalidResponse');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! Map) {
      if (response.statusCode == 400) {
        throw const TeamRecommendationApiException('invalidRequest');
      }
      throw const TeamRecommendationApiException('requestFailed');
    }
    return _parseJob(Map<String, Object?>.from(decoded));
  }

  Uri _uri(String path) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        (base.scheme != 'https' && !_localHttp(base))) {
      throw const TeamRecommendationApiException('notConfigured');
    }
    return base.resolve(path);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

bool _localHttp(Uri uri) =>
    uri.scheme == 'http' &&
    const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);

TeamSimulationJob _parseJob(Map<String, Object?> json) {
  final jobId = _string(json['jobId'], RegExp(r'^[0-9a-fA-F-]{36}$'));
  final statusName = _string(
    json['status'],
    RegExp(r'^(queued|running|completed|failed|expired)$'),
  );
  final status = TeamSimulationJobStatus.values.firstWhere(
    (value) => value.name == statusName,
  );
  return TeamSimulationJob(
    jobId: jobId,
    status: status,
    result:
        json['result'] is Map
            ? _parseResult(Map<String, Object?>.from(json['result'] as Map))
            : null,
    errorCode: json['errorCode'] is String ? json['errorCode'] as String : null,
  );
}

TeamRecommendationResult _parseResult(Map<String, Object?> json) {
  final gcsim = _map(json['gcsim']);
  final rawRecommendations = _list(json['recommendations'], 20);
  return TeamRecommendationResult(
    attackerId: _string(json['attackerId'], RegExp(r'^\d{5,12}$')),
    generatedAt: DateTime.parse(
      _string(json['generatedAt'], RegExp(r'^.{1,40}$')),
    ),
    gcsimVersion: _string(gcsim['version'], RegExp(r'^v[0-9.]{1,20}$')),
    iterations: _int(gcsim['iterations'], 1, 100000),
    gcsimEnabled: _bool(gcsim['enabled']),
    recommendations:
        rawRecommendations
            .map((raw) => _parseRecommendation(_map(raw)))
            .toList(),
    warning: json['warning'] is String ? json['warning'] as String : null,
  );
}

TeamRecommendation _parseRecommendation(Map<String, Object?> json) {
  final members =
      _list(
        json['members'],
        4,
      ).map((value) => _string(value, RegExp(r'^\d{5,12}$'))).toList();
  if (members.length != 4 || members.toSet().length != 4) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  final alternatives = <String, List<String>>{};
  for (final entry in _map(json['alternatives']).entries) {
    alternatives[entry.key] =
        _list(
          entry.value,
          16,
        ).map((value) => _string(value, RegExp(r'^\d{5,12}$'))).toList();
  }
  return TeamRecommendation(
    members: members,
    score: _double(json['score'], 0, 1),
    estimatedDps:
        json['estimatedDps'] == null
            ? null
            : _double(json['estimatedDps'], 0, 1000000000),
    simulationStatus: _string(
      json['simulationStatus'],
      RegExp(r'^(simulated|observed|ruleBased|manual)$'),
    ),
    sourceTypes:
        _list(
          json['sourceTypes'],
          8,
        ).map((value) => _string(value, RegExp(r'^[A-Za-z]+$'))).toList(),
    rotationConfidence: _string(
      json['rotationConfidence'],
      RegExp(r'^(high|medium|low)$'),
    ),
    observedByAza: _bool(json['observedByAza']),
    isCached: _bool(json['isCached']),
    isStale: _bool(json['isStale']),
    inputQuality: SimulationInputQuality.values.firstWhere(
      (value) =>
          value.name ==
          _string(
            json['inputQuality'],
            RegExp(r'^(exact|partial|defaulted|unsupported)$'),
          ),
    ),
    reasons:
        _list(
          json['reasons'],
          16,
        ).map((value) => _string(value, RegExp(r'^.{1,160}$'))).toList(),
    alternatives: alternatives,
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, int max) {
  if (value is! List || value.length > max) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return value.cast<Object?>();
}

String _string(Object? value, RegExp pattern) {
  if (value is! String || !pattern.hasMatch(value)) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return value;
}

int _int(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return value;
}

double _double(Object? value, double min, double max) {
  if (value is! num ||
      !value.toDouble().isFinite ||
      value < min ||
      value > max) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return value.toDouble();
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  return value;
}
