import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/battle_statistics/battle_statistics.dart';
import '../../domain/repositories/battle_statistics_repository.dart';

enum BattleStatsRemoteFailure {
  notConfigured,
  network,
  timeout,
  invalidResponse,
  unavailable,
}

class BattleStatsRemoteException implements Exception {
  const BattleStatsRemoteException(this.failure);

  final BattleStatsRemoteFailure failure;
}

class BackendBattleStatisticsApi implements BattleStatisticsRemoteSource {
  BackendBattleStatisticsApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const _manifestMaxBytes = 256 * 1024;
  static const _bundleMaxBytes = 4 * 1024 * 1024;
  static const _userAgent =
      'genshin-builder-mobile/0.1 (battle-statistics-backend)';

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<BattleStatsManifestFetchResult> fetchManifest({String? etag}) async {
    final response = await _get(
      _uri('/api/battle-statistics/manifest'),
      maxBytes: _manifestMaxBytes,
      headers: etag == null ? const {} : {'If-None-Match': etag},
    );
    if (response.statusCode == 304) {
      return const BattleStatsManifestFetchResult(notModified: true);
    }
    final data = _successData(response);
    _exactKeys(data, {'schemaVersion', 'abyss', 'stygian'});
    final schemaVersion = _integer(data['schemaVersion'], min: 1, max: 100);
    final items = <BattleStatsContentType, BattleStatsManifestItem>{};
    for (final contentType in BattleStatsContentType.values) {
      final raw = data[contentType.name];
      if (raw == null) continue;
      final item = _object(raw);
      _exactKeys(item, {'seasonId', 'revision', 'payloadHash', 'updatedAt'});
      items[contentType] = BattleStatsManifestItem(
        contentType: contentType,
        seasonId: _safeString(
          item['seasonId'],
          RegExp(r'^[A-Za-z0-9._:-]{1,128}$'),
        ),
        revision: _integer(item['revision'], min: 1, max: 2147483647),
        payloadHash: _hash(item['payloadHash']),
        updatedAt: _date(item['updatedAt']),
      );
    }
    final responseEtag = response.headers['etag'];
    return BattleStatsManifestFetchResult(
      notModified: false,
      manifest: BattleStatsManifest(
        schemaVersion: schemaVersion,
        items: items,
        etag:
            responseEtag != null && responseEtag.length <= 256
                ? responseEtag
                : null,
      ),
    );
  }

  @override
  Future<BattleStatsBundlePage> fetchBundlePage({
    required BattleStatsContentType contentType,
    required int revision,
    required int page,
  }) async {
    final response = await _get(
      _uri('/api/battle-statistics/bundle').replace(
        queryParameters: {
          'type': contentType.name,
          'revision': '$revision',
          'page': '$page',
        },
      ),
      maxBytes: _bundleMaxBytes,
    );
    final data = _successData(response);
    _exactKeys(data, {
      'schemaVersion',
      'source',
      'contentType',
      'sourceVersion',
      'seasonId',
      'revision',
      'payloadHash',
      'sourceUpdatedAt',
      'sampleSize',
      'metadata',
      'page',
      'pageCount',
      'teams',
      'characters',
    });
    if (data['source'] != 'YShelper' ||
        data['contentType'] != contentType.name) {
      _invalid();
    }
    final parsedPage = _integer(data['page'], min: 0, max: 100000);
    final pageCount = _integer(data['pageCount'], min: 1, max: 100000);
    if (parsedPage != page || parsedPage >= pageCount) _invalid();
    final teams = _list(
      data['teams'],
      maxLength: 500,
    ).map((item) => _parseTeam(_object(item))).toList(growable: false);
    final characters = _list(
      data['characters'],
      maxLength: 500,
    ).map((item) => _parseCharacter(_object(item))).toList(growable: false);
    return BattleStatsBundlePage(
      schemaVersion: _integer(data['schemaVersion'], min: 1, max: 100),
      contentType: contentType,
      sourceVersion: _safeString(
        data['sourceVersion'],
        RegExp(r'^[A-Za-z0-9._-]{1,64}$'),
      ),
      seasonId: _safeString(
        data['seasonId'],
        RegExp(r'^[A-Za-z0-9._:-]{1,128}$'),
      ),
      revision: _integer(data['revision'], min: 1, max: 2147483647),
      payloadHash: _hash(data['payloadHash']),
      sourceUpdatedAt: _date(data['sourceUpdatedAt']),
      sampleSize: _optionalInteger(data['sampleSize']),
      page: parsedPage,
      pageCount: pageCount,
      teams: teams,
      characters: characters,
    );
  }

  RemoteBattleTeam _parseTeam(Map<String, Object?> value) {
    _exactKeys(value, {
      'teamKey',
      'members',
      'usageRate',
      'usageCount',
      'rank',
      'side',
      'stageKey',
      'sampleSize',
    });
    final members = _list(
      value['members'],
      maxLength: 4,
    ).map((item) => _characterId(item)).toList(growable: false);
    if (members.length != 4 || members.toSet().length != 4) _invalid();
    final expectedKey = [...members]..sort();
    if (value['teamKey'] != expectedKey.join(':')) _invalid();
    return RemoteBattleTeam(
      teamKey: value['teamKey'] as String,
      members: members,
      usageRate: _rate(value['usageRate']),
      usageCount: _optionalInteger(value['usageCount']),
      rank: _optionalInteger(value['rank'], min: 1),
      side: _optionalScope(value['side']),
      stageKey: _optionalScope(value['stageKey']),
      sampleSize: _optionalInteger(value['sampleSize']),
    );
  }

  RemoteBattleCharacterUsage _parseCharacter(Map<String, Object?> value) {
    _exactKeys(value, {
      'characterId',
      'usageRate',
      'usageCount',
      'rank',
      'side',
      'ownershipRate',
      'usageAmongOwnersRate',
      'sampleSize',
    });
    return RemoteBattleCharacterUsage(
      characterId: _characterId(value['characterId']),
      usageRate: _rate(value['usageRate']),
      usageCount: _optionalInteger(value['usageCount']),
      rank: _optionalInteger(value['rank'], min: 1),
      side: _optionalScope(value['side']),
      ownershipRate: _optionalRate(value['ownershipRate']),
      usageAmongOwnersRate: _optionalRate(value['usageAmongOwnersRate']),
      sampleSize: _optionalInteger(value['sampleSize']),
    );
  }

  Future<_BackendResponse> _get(
    Uri uri, {
    required int maxBytes,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        ...headers,
      });
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(timeout);
      final declared = streamed.contentLength;
      if (declared != null && declared > maxBytes) _invalid();
      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in streamed.stream.timeout(timeout)) {
        length += chunk.length;
        if (length > maxBytes) _invalid();
        builder.add(chunk);
      }
      return _BackendResponse(
        statusCode: streamed.statusCode,
        headers: streamed.headers,
        bytes: builder.takeBytes(),
      );
    } on TimeoutException {
      throw const BattleStatsRemoteException(BattleStatsRemoteFailure.timeout);
    } on BattleStatsRemoteException {
      rethrow;
    } on http.ClientException {
      throw const BattleStatsRemoteException(BattleStatsRemoteFailure.network);
    } catch (_) {
      throw const BattleStatsRemoteException(BattleStatsRemoteFailure.network);
    }
  }

  Map<String, Object?> _successData(_BackendResponse response) {
    if (response.statusCode != 200) {
      throw const BattleStatsRemoteException(
        BattleStatsRemoteFailure.unavailable,
      );
    }
    final contentType =
        response.headers['content-type']?.split(';').first.trim();
    if (contentType != 'application/json') _invalid();
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bytes, allowMalformed: false),
      );
      final envelope = _object(decoded);
      _exactKeys(envelope, {'ok', 'data'});
      if (envelope['ok'] != true) _invalid();
      return _object(envelope['data']);
    } catch (_) {
      _invalid();
    }
  }

  Uri _uri(String path) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw const BattleStatsRemoteException(
        BattleStatsRemoteFailure.notConfigured,
      );
    }
    final Uri base;
    try {
      base = Uri.parse(trimmed);
    } on FormatException {
      throw const BattleStatsRemoteException(
        BattleStatsRemoteFailure.notConfigured,
      );
    }
    if (!base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'https' && !_isLocalDevelopmentHttp(base)) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const BattleStatsRemoteException(
        BattleStatsRemoteFailure.notConfigured,
      );
    }
    return base.resolve(path);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _BackendResponse {
  const _BackendResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;
}

bool _isLocalDevelopmentHttp(Uri uri) {
  if (uri.scheme != 'http') return false;
  return const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
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

void _exactKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) _invalid();
}

String _safeString(Object? value, RegExp pattern) {
  if (value is! String || !pattern.hasMatch(value)) _invalid();
  return value;
}

String _characterId(Object? value) => _safeString(value, RegExp(r'^\d{4,16}$'));

String _hash(Object? value) =>
    _safeString(value, RegExp(r'^sha256:[a-f0-9]{64}$'));

String? _optionalScope(Object? value) =>
    value == null
        ? null
        : _safeString(value, RegExp(r'^[A-Za-z0-9._:-]{1,64}$'));

int _integer(Object? value, {required int min, required int max}) {
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

int? _optionalInteger(Object? value, {int min = 0}) {
  if (value == null) return null;
  return _integer(value, min: min, max: 2147483647);
}

double _rate(Object? value) {
  if (value is! num) _invalid();
  final rate = value.toDouble();
  if (!rate.isFinite || rate < 0 || rate > 1) _invalid();
  return rate;
}

double? _optionalRate(Object? value) => value == null ? null : _rate(value);

DateTime _date(Object? value) {
  if (value is! String || value.length > 40) _invalid();
  final date = DateTime.tryParse(value);
  if (date == null) _invalid();
  return date;
}

Never _invalid() =>
    throw const BattleStatsRemoteException(
      BattleStatsRemoteFailure.invalidResponse,
    );
