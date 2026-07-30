import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/team_recommendation/team_recommendation.dart';
import '../../domain/team_recommendation/team_template_replacement.dart';

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

  Future<List<PublishedTeamTemplate>> getTemplates() async {
    final json = await _sendJson(
      () => _client.get(
        _uri('/api/team-templates'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'genshin-builder-mobile/0.1 (team-templates)',
        },
      ),
    );
    return _list(
      json['templates'],
      100,
    ).map((value) => _parseTemplate(_map(value))).toList();
  }

  Future<TeamReplacementResult> getReplacement({
    required String templateId,
    required String characterId,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{5,40}$').hasMatch(templateId) ||
        !RegExp(r'^\d{5,12}(?:-[a-zA-Z0-9_-]{1,24})?$').hasMatch(characterId)) {
      throw const TeamRecommendationApiException('invalidRequest');
    }
    final json = await _sendJson(
      () => _client.get(
        _uri('/api/team-templates/$templateId/replacements/$characterId'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'genshin-builder-mobile/0.1 (team-replacements)',
        },
      ),
    );
    return _parseReplacementResult(json);
  }

  Future<TeamSimulationJob> _send(Future<http.Response> Function() call) async {
    return _parseJob(await _sendJson(call));
  }

  Future<Map<String, Object?>> _sendJson(
    Future<http.Response> Function() call,
  ) async {
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
      if (response.statusCode == 404) {
        throw const TeamRecommendationApiException('notFound');
      }
      throw const TeamRecommendationApiException('requestFailed');
    }
    return Map<String, Object?>.from(decoded);
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

PublishedTeamTemplate _parseTemplate(Map<String, Object?> json) {
  final members =
      _list(json['members'], 4).map((value) {
        final member = _map(value);
        return TeamTemplateMember(
          characterId: _string(
            member['characterId'],
            RegExp(r'^\d{5,12}(?:-[a-zA-Z0-9_-]{1,24})?$'),
          ),
          role: _string(
            member['role'],
            RegExp(r'^(main_dps|sub_dps|support|healer|shielder|flex)$'),
          ),
          slotIndex: _int(member['slotIndex'], 0, 3),
        );
      }).toList();
  if (members.length != 4 ||
      members.map((value) => value.characterId).toSet().length != 4 ||
      members.map((value) => value.slotIndex).toSet().length != 4) {
    throw const TeamRecommendationApiException('invalidResponse');
  }
  members.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
  Uri? sourceUrl;
  if (json['sourceUrl'] is String && (json['sourceUrl'] as String).isNotEmpty) {
    sourceUrl = Uri.tryParse(json['sourceUrl'] as String);
    if (sourceUrl == null ||
        sourceUrl.scheme != 'https' ||
        !sourceUrl.hasAuthority ||
        sourceUrl.userInfo.isNotEmpty) {
      throw const TeamRecommendationApiException('invalidResponse');
    }
  }
  return PublishedTeamTemplate(
    id: _string(json['id'], RegExp(r'^[a-zA-Z0-9_-]{5,40}$')),
    name: _string(json['name'], RegExp(r'^.{1,160}$')),
    archetype: _string(json['archetype'], RegExp(r'^.{0,80}$')),
    members: members,
    source: _string(json['source'], RegExp(r'^(genshinbuilds|local|manual)$')),
    sourceUrl: sourceUrl,
    dataVersion: _string(json['dataVersion'], RegExp(r'^.{1,80}$')),
    updatedAt: DateTime.parse(_string(json['updatedAt'], RegExp(r'^.{1,40}$'))),
  );
}

TeamReplacementResult _parseReplacementResult(Map<String, Object?> json) {
  final analysis = _map(json['slotAnalysis']);
  return TeamReplacementResult(
    templateId: _string(json['templateId'], RegExp(r'^[a-zA-Z0-9_-]{5,40}$')),
    replacedCharacterId: _string(
      json['replacedCharacterId'],
      RegExp(r'^\d{5,12}(?:-[a-zA-Z0-9_-]{1,24})?$'),
    ),
    generatedAt: DateTime.parse(
      _string(json['generatedAt'], RegExp(r'^.{1,40}$')),
    ),
    dataVersion: _string(json['dataVersion'], RegExp(r'^.{1,80}$')),
    isStale: _bool(json['isStale']),
    source: _string(json['source'], RegExp(r'^(deepseek|rules|manual)$')),
    requiredFunctions: _shortStrings(analysis['requiredFunctions'], 32),
    preferredFunctions: _shortStrings(analysis['preferredFunctions'], 32),
    dependencies: _shortStrings(analysis['dependencies'], 32),
    replacementRisks: _shortStrings(analysis['replacementRisks'], 32),
    candidates:
        _list(
          json['candidates'],
          20,
        ).map((value) => _parseReplacementCandidate(_map(value))).toList(),
  );
}

ReplacementCandidate _parseReplacementCandidate(Map<String, Object?> json) {
  final evaluation = _map(json['teamEvaluation']);
  return ReplacementCandidate(
    characterId: _string(
      json['characterId'],
      RegExp(r'^\d{5,12}(?:-[a-zA-Z0-9_-]{1,24})?$'),
    ),
    element: _string(
      json['element'],
      RegExp(r'^(pyro|hydro|electro|cryo|anemo|geo|dendro|unknown)$'),
    ),
    roles: _shortStrings(json['roles'], 32),
    tags: _shortStrings(json['tags'], 32),
    compatibilityScore: _double(json['compatibilityScore'], 0, 100),
    category: switch (_string(
      json['category'],
      RegExp(r'^(optimal|conditional|compromise|not_recommended)$'),
    )) {
      'optimal' => ReplacementCategory.optimal,
      'conditional' => ReplacementCategory.conditional,
      'compromise' => ReplacementCategory.compromise,
      _ => ReplacementCategory.notRecommended,
    },
    confidence: _double(json['confidence'], 0, 1),
    reasons: _shortStrings(json['reasons'], 3),
    tradeoffs: _shortStrings(json['tradeoffs'], 3),
    requiredChanges: _shortStrings(json['requiredChanges'], 3),
    teamEvaluation: ReplacementTeamEvaluation(
      reactionViability: _double(evaluation['reactionViability'], 0, 100),
      damageBalance: _double(evaluation['damageBalance'], 0, 100),
      sustain: _double(evaluation['sustain'], 0, 100),
      energy: _double(evaluation['energy'], 0, 100),
      fieldTimeBalance: _double(evaluation['fieldTimeBalance'], 0, 100),
    ),
    deterministicPenalty: _int(json['deterministicPenalty'], 0, 100),
    finalScore: _double(json['finalScore'], 0, 100),
  );
}

List<String> _shortStrings(Object? value, int max) =>
    _list(
      value,
      max,
    ).map((item) => _string(item, RegExp(r'^.{1,160}$'))).toList();

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
  final rawRecommendations = _list(json['recommendations'], 20);
  return TeamRecommendationResult(
    attackerId: _string(json['attackerId'], RegExp(r'^\d{5,12}$')),
    generatedAt: DateTime.parse(
      _string(json['generatedAt'], RegExp(r'^.{1,40}$')),
    ),
    recommendations:
        rawRecommendations
            .map((raw) => _parseRecommendation(_map(raw)))
            .toList(),
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
    simulationStatus: _string(
      json['simulationStatus'],
      RegExp(r'^(observed|ruleBased|manual)$'),
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
