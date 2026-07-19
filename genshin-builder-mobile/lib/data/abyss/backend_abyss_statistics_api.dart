import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/abyss/abyss_statistics.dart';

class BackendAbyssStatisticsApi {
  BackendAbyssStatisticsApi({
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
  static const _userAgent =
      'genshin-builder-mobile/0.1 (abyss-statistics-backend)';

  Future<AbyssStatistics> fetchLatest() async {
    final uri = _statisticsUri();
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
      throw const AbyssStatisticsException(AbyssStatisticsFailure.timeout);
    } on http.ClientException {
      throw const AbyssStatisticsException(AbyssStatisticsFailure.networkError);
    } catch (_) {
      throw const AbyssStatisticsException(AbyssStatisticsFailure.networkError);
    }

    if (response.bodyBytes.length > _maxResponseBytes) {
      throw const AbyssStatisticsException(
        AbyssStatisticsFailure.invalidResponse,
      );
    }

    final decoded = _decodeObject(response.bodyBytes);
    if (response.statusCode != 200) {
      throw AbyssStatisticsException(
        _failureFromErrorEnvelope(decoded, response.statusCode),
      );
    }
    if (decoded['ok'] != true) {
      throw const AbyssStatisticsException(
        AbyssStatisticsFailure.invalidResponse,
      );
    }
    return _parseStatistics(_object(decoded['data']));
  }

  Uri _statisticsUri() {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const AbyssStatisticsException(
        AbyssStatisticsFailure.notConfigured,
      );
    }
    final Uri base;
    try {
      base = Uri.parse(trimmed);
    } on FormatException {
      throw const AbyssStatisticsException(
        AbyssStatisticsFailure.notConfigured,
      );
    }
    if (!base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'https' && !_isLocalDevelopmentHttp(base)) ||
        base.userInfo.isNotEmpty) {
      throw const AbyssStatisticsException(
        AbyssStatisticsFailure.notConfigured,
      );
    }
    return base.resolve('/api/abyss/statistics');
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

bool _isLocalDevelopmentHttp(Uri uri) {
  if (uri.scheme != 'http') return false;
  return const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
}

AbyssStatistics _parseStatistics(Map<String, Object?> json) {
  final version = _object(json['version']);
  final metadata = _object(json['metadata']);
  final characters = _list(json['characters'], maxLength: 256);
  final teams = _list(json['teams'], maxLength: 400);

  return AbyssStatistics(
    version: AbyssVersion(
      scheduleId: _integer(version['scheduleId'], min: 0, max: 1000000),
      periodStart: _date(version['periodStart']),
      periodEnd: _date(version['periodEnd']),
      sourceApiVersion: _safeString(
        version['sourceApiVersion'],
        RegExp(r'^[A-Za-z0-9._-]{1,32}$'),
      ),
    ),
    metadata: AbyssStatisticsMetadata(
      source: _source(metadata['source']),
      fetchedAt: _date(metadata['fetchedAt']),
      expiresAt: _date(metadata['expiresAt']),
      sourceUpdatedAt: _date(metadata['sourceUpdatedAt']),
      isStale: _boolean(metadata['isStale']),
      sampleSize: _integer(metadata['sampleSize'], min: 0, max: 10000000),
      referenceSampleSize: _integer(
        metadata['referenceSampleSize'],
        min: 0,
        max: 10000000,
      ),
      collectionProgress: _rate(metadata['collectionProgress']),
      warningCode: _optionalFailure(metadata['warningCode']),
      upstreamErrorCode: _optionalFailure(metadata['upstreamErrorCode']),
    ),
    characters: [for (final raw in characters) _parseCharacter(_object(raw))],
    teams: [for (final raw in teams) _parseTeam(_object(raw))],
  );
}

AbyssCharacterStatistic _parseCharacter(Map<String, Object?> json) {
  return AbyssCharacterStatistic(
    characterId: _safeString(json['characterId'], RegExp(r'^\d{8,16}$')),
    usageRate: _rate(json['usageRate']),
    ownershipRate: _rate(json['ownershipRate']),
    usageAmongOwnersRate: _rate(json['usageAmongOwnersRate']),
    upperHalfRate: _optionalRate(json['upperHalfRate']),
    lowerHalfRate: _optionalRate(json['lowerHalfRate']),
    constellationRates: [
      for (final raw in _list(json['constellationRates'], maxLength: 7))
        _parseConstellation(_object(raw)),
    ],
    weapons: [
      for (final raw in _list(json['weapons'], maxLength: 128))
        _parseRateStatistic(_object(raw)),
    ],
    artifacts: [
      for (final raw in _list(json['artifacts'], maxLength: 64))
        _parseArtifact(_object(raw)),
    ],
  );
}

AbyssConstellationStatistic _parseConstellation(Map<String, Object?> json) {
  return AbyssConstellationStatistic(
    constellation: _integer(json['constellation'], min: 0, max: 6),
    rate: _rate(json['rate']),
  );
}

AbyssRateStatistic _parseRateStatistic(Map<String, Object?> json) {
  return AbyssRateStatistic(
    id: _safeString(json['id'], RegExp(r'^\d{4,16}$')),
    usageRate: _rate(json['usageRate']),
  );
}

AbyssArtifactStatistic _parseArtifact(Map<String, Object?> json) {
  return AbyssArtifactStatistic(
    setPieces: [
      for (final raw in _list(json['setPieces'], maxLength: 2))
        AbyssArtifactSetPiece(
          artifactSetId: _safeString(
            _object(raw)['artifactSetId'],
            RegExp(r'^\d{4,16}$'),
          ),
          pieces: _integer(_object(raw)['pieces'], min: 1, max: 5),
        ),
    ],
    usageRate: _rate(json['usageRate']),
  );
}

AbyssTeamStatistic _parseTeam(Map<String, Object?> json) {
  final members = _list(json['members'], maxLength: 4);
  if (members.length != 4) _invalid();
  return AbyssTeamStatistic(
    half: switch (_safeString(json['half'], RegExp(r'^(upper|lower)$'))) {
      'upper' => AbyssTeamHalf.upper,
      'lower' => AbyssTeamHalf.lower,
      _ =>
        throw const AbyssStatisticsException(
          AbyssStatisticsFailure.invalidResponse,
        ),
    },
    members: [
      for (final member in members)
        AbyssTeamMember(
          characterId: _safeString(member, RegExp(r'^\d{8,16}$')),
        ),
    ],
    usageRate: _rate(json['usageRate']),
    ownershipRate: _rate(json['ownershipRate']),
    usageAmongOwnersRate: _rate(json['usageAmongOwnersRate']),
  );
}

Map<String, Object?> _decodeObject(List<int> bytes) {
  try {
    final Object? decoded = jsonDecode(
      utf8.decode(bytes, allowMalformed: false),
    );
    return _object(decoded);
  } catch (_) {
    throw const AbyssStatisticsException(
      AbyssStatisticsFailure.invalidResponse,
    );
  }
}

AbyssStatisticsFailure _failureFromErrorEnvelope(
  Map<String, Object?> json,
  int status,
) {
  final error = json['error'];
  if (error is Map) {
    try {
      final code = _object(error)['code'];
      if (code is String) return _failure(code);
    } catch (_) {
      // Status code mapping below remains the safe fallback.
    }
  }
  if (status == 429) return AbyssStatisticsFailure.rateLimited;
  if (status == 504) return AbyssStatisticsFailure.timeout;
  if (status >= 500) return AbyssStatisticsFailure.networkError;
  return AbyssStatisticsFailure.unknownError;
}

AbyssDataSource _source(Object? value) {
  if (value == 'AZA.GG') return AbyssDataSource.aza;
  _invalid();
}

AbyssStatisticsFailure _failure(String value) {
  for (final failure in AbyssStatisticsFailure.values) {
    if (failure.name == value) return failure;
  }
  return AbyssStatisticsFailure.unknownError;
}

AbyssStatisticsFailure? _optionalFailure(Object? value) {
  if (value == null) return null;
  if (value is! String) _invalid();
  return _failure(value);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) _invalid();
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) _invalid();
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _list(Object? value, {required int maxLength}) {
  if (value is! List || value.length > maxLength) _invalid();
  return value.cast<Object?>();
}

String _safeString(Object? value, RegExp pattern) {
  if (value is! String || !pattern.hasMatch(value)) _invalid();
  return value;
}

int _integer(Object? value, {required int min, required int max}) {
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

double _rate(Object? value) {
  if (value is! num) _invalid();
  final result = value.toDouble();
  if (!result.isFinite || result < 0 || result > 1) _invalid();
  return result;
}

double? _optionalRate(Object? value) => value == null ? null : _rate(value);

bool _boolean(Object? value) {
  if (value is! bool) _invalid();
  return value;
}

DateTime _date(Object? value) {
  if (value is! String || value.length > 40) _invalid();
  final result = DateTime.tryParse(value);
  if (result == null) _invalid();
  return result;
}

Never _invalid() =>
    throw const AbyssStatisticsException(
      AbyssStatisticsFailure.invalidResponse,
    );
