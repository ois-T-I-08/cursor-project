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

  // 正式 recommendedStats を targets へも反映（targets が空のとき優先）
  if (targets.isEmpty) {
    for (final item in _list(json['recommendedStats'], maxLength: 20)) {
      final map = _object(item);
      final stat = parseGuideStatKey(_string(map['stat']));
      if (stat == null) continue;
      targets.add(
        BuildStatTarget(
          stat: stat,
          recommended: _optionalDouble(map['recommended']),
          min: _optionalDouble(map['minimum'] ?? map['min']),
          max: _optionalDouble(map['maximum'] ?? map['max']),
          unit: map['unit'] is String ? map['unit'] as String : null,
        ),
      );
    }
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
        id: _nullableString(map['id']),
        videoId: _string(map['videoId']),
        title: _string(map['title'] ?? map['videoTitle']),
        channelTitle: _string(map['channelTitle'] ?? map['channelName']),
        sourceUrl: _string(map['sourceUrl']),
        publishedAt: _optionalDate(map['publishedAt']),
        channelId: map['channelId'] is String
            ? (map['channelId'] as String).trim()
            : null,
        reviewedAt: _optionalDate(map['reviewedAt']),
        gameVersion: map['gameVersion'] is String
            ? (map['gameVersion'] as String).trim()
            : null,
      ),
    );
  }
  final citationByVideoId = <String, GuideCitation>{
    for (final s in sources)
      if (s.videoId.isNotEmpty) s.videoId: s.toCitation(),
  };
  final citationById = <String, GuideCitation>{
    for (final s in sources)
      if (s.id != null && s.id!.isNotEmpty) s.id!: s.toCitation(),
  };

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

  final mainStats = <GuideMainStatRecommendation>[];
  for (final item in _list(json['mainStats'], maxLength: 6)) {
    final map = _object(item);
    final slot = _parseArtifactSlot(_string(map['slot']));
    if (slot == null) continue;
    final stats = <String>[];
    for (final raw in _list(map['primaryStats'], maxLength: 4)) {
      if (raw is String && raw.trim().isNotEmpty) stats.add(raw.trim());
    }
    for (final raw in _list(map['alternativeStats'], maxLength: 4)) {
      if (raw is String && raw.trim().isNotEmpty) stats.add(raw.trim());
    }
    if (stats.isEmpty) {
      for (final raw in _list(map['stats'], maxLength: 6)) {
        if (raw is String && raw.trim().isNotEmpty) stats.add(raw.trim());
      }
    }
    if (stats.isEmpty) continue;
    mainStats.add(
      GuideMainStatRecommendation(
        slot: slot,
        candidates: stats,
        condition: map['condition'] is String
            ? (map['condition'] as String).trim()
            : null,
        citation: _resolveCitation(
          map['citationId'] ?? map['source'] ?? map['citation'],
          citationById,
          citationByVideoId,
        ),
      ),
    );
  }

  final weapons = <GuideWeaponRecommendation>[];
  final weaponList = json['weapons'] ?? json['weaponRecommendations'];
  for (final item in _list(weaponList, maxLength: 12)) {
    final map = _object(item);
    final weaponId = _nullableString(map['weaponId'] ?? map['id']);
    final displayName = _nullableString(map['displayName'] ?? map['name']);
    if ((weaponId == null || weaponId.isEmpty) &&
        (displayName == null || displayName.isEmpty)) {
      continue;
    }
    final conditions = <String>[];
    for (final raw in _list(map['conditions'], maxLength: 8)) {
      if (raw is String && raw.trim().isNotEmpty) {
        conditions.add(raw.trim());
      }
    }
    final originRaw = _nullableString(map['dataOrigin']);
    final dataOrigin = originRaw == 'legacy_preference'
        ? GuideWeaponDataOrigin.legacyPreference
        : GuideWeaponDataOrigin.structured;
    weapons.add(
      GuideWeaponRecommendation(
        weaponId: weaponId,
        displayName: displayName,
        rank: _optionalInt(map['rank']),
        recommendationLevel:
            parseGuideRecommendationLevel(_nullableString(map['recommendationLevel'])),
        reason: _nullableString(map['reason']),
        conditions: conditions,
        role: _nullableString(map['role']),
        citation: _resolveCitation(
          map['citationId'] ?? map['source'] ?? map['citation'],
          citationById,
          citationByVideoId,
        ),
        dataOrigin: dataOrigin,
      ),
    );
  }

  final artifactRecommendations = <GuideArtifactRecommendation>[];
  final artifactList =
      json['artifactRecommendations'] ?? json['artifactSets'];
  for (final item in _list(artifactList, maxLength: 12)) {
    final map = _object(item);
    final parts = <GuideArtifactSetPart>[];
    for (final rawPart in _list(map['sets'], maxLength: 4)) {
      final partMap = _object(rawPart);
      final setId = _nullableString(partMap['setId'] ?? partMap['id']);
      final pieces = _optionalInt(partMap['pieces']) ?? 0;
      if (setId == null || setId.isEmpty || pieces <= 0) continue;
      parts.add(GuideArtifactSetPart(setId: setId, pieces: pieces));
    }
    if (parts.isEmpty) continue;
    final conditions = <String>[];
    for (final raw in _list(map['conditions'], maxLength: 8)) {
      if (raw is String && raw.trim().isNotEmpty) {
        conditions.add(raw.trim());
      }
    }
    artifactRecommendations.add(
      GuideArtifactRecommendation(
        sets: parts,
        rank: _optionalInt(map['rank']),
        recommendationLevel:
            parseGuideRecommendationLevel(_nullableString(map['recommendationLevel'])),
        reason: _nullableString(map['reason']),
        conditions: conditions,
        role: _nullableString(map['role']),
        citation: _resolveCitation(
          map['citationId'] ?? map['source'] ?? map['citation'],
          citationById,
          citationByVideoId,
        ),
        isAlternative: map['isAlternative'] == true,
      ),
    );
  }

  final originRaw = _string(json['origin']);
  final origin = originRaw == 'merged'
      ? BuildRecommendationOrigin.merged
      : BuildRecommendationOrigin.singleVideo;

  final priorityRaw = context['investmentPriority'] is String
      ? context['investmentPriority'] as String
      : (json['investmentPriority'] is String
          ? json['investmentPriority'] as String
          : null);

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
    mainStats: mainStats,
    weapons: weapons,
    artifactRecommendations: artifactRecommendations,
    lastVerifiedAt: _optionalDate(json['lastVerifiedAt']),
    publishedAt: _optionalDate(json['publishedAt']),
    role: context['role'] is String ? context['role'] as String : null,
    teamArchetype: context['teamArchetype'] is String
        ? context['teamArchetype'] as String
        : null,
    weaponPreference: context['weaponPreference'] is String
        ? context['weaponPreference'] as String
        : null,
    notes: context['notes'] is String ? context['notes'] as String : null,
    investmentPriority: parseInvestmentPriority(priorityRaw),
    gameVersion: context['gameVersion'] is String
        ? context['gameVersion'] as String
        : (json['gameVersion'] is String ? json['gameVersion'] as String : null),
  );
}

GuideArtifactSlot? _parseArtifactSlot(String raw) {
  switch (raw) {
    case 'sands':
      return GuideArtifactSlot.sands;
    case 'goblet':
      return GuideArtifactSlot.goblet;
    case 'circlet':
      return GuideArtifactSlot.circlet;
    default:
      return null;
  }
}

GuideCitation? _resolveCitation(
  Object? raw,
  Map<String, GuideCitation> byId,
  Map<String, GuideCitation> byVideoId,
) {
  if (raw is String) {
    final key = raw.trim();
    if (key.isEmpty) return null;
    return byId[key] ?? byVideoId[key] ?? GuideCitation(videoId: key);
  }
  final map = _object(raw);
  if (map.isEmpty) return null;
  final citationId = _nullableString(map['citationId'] ?? map['id']);
  if (citationId != null && byId.containsKey(citationId)) {
    return byId[citationId];
  }
  final videoId = _nullableString(map['videoId']);
  if (videoId != null && byVideoId.containsKey(videoId)) {
    final base = byVideoId[videoId]!;
    return GuideCitation(
      videoId: base.videoId,
      videoTitle: _nullableString(map['videoTitle']) ?? base.videoTitle,
      channelId: _nullableString(map['channelId']) ?? base.channelId,
      channelName: _nullableString(map['channelName'] ?? map['channelTitle']) ??
          base.channelName,
      publishedAt: _optionalDate(map['publishedAt']) ?? base.publishedAt,
      reviewedAt: _optionalDate(map['reviewedAt']) ?? base.reviewedAt,
      gameVersion: _nullableString(map['gameVersion']) ?? base.gameVersion,
      sourceUrl: _nullableString(map['sourceUrl']) ?? base.sourceUrl,
    );
  }
  final citation = GuideCitation(
    videoId: videoId,
    videoTitle: _nullableString(map['videoTitle'] ?? map['title']),
    channelId: _nullableString(map['channelId']),
    channelName: _nullableString(map['channelName'] ?? map['channelTitle']),
    publishedAt: _optionalDate(map['publishedAt']),
    reviewedAt: _optionalDate(map['reviewedAt']),
    gameVersion: _nullableString(map['gameVersion']),
    sourceUrl: _nullableString(map['sourceUrl']),
  );
  return citation.hasAnyField ? citation : null;
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
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
