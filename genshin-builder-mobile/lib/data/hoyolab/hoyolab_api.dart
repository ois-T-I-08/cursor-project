import 'dart:convert';

import 'package:http/http.dart' as http;

import 'hoyolab_auth.dart';
import 'hoyolab_constants.dart';
import 'hoyolab_exceptions.dart';
import 'hoyolab_http_guard.dart';
import 'models/daily_note.dart';
import 'models/game_record.dart';

class HoyolabApiResult<T> {
  const HoyolabApiResult({
    required this.retcode,
    required this.message,
    this.data,
  });

  final int retcode;
  final String message;
  final T? data;

  bool get hasError => retcode != 0;

  factory HoyolabApiResult.fromJson(
    Map<String, dynamic> json,
    T Function(Object? obj) fromJsonT,
  ) => HoyolabApiResult(
    retcode: json['retcode'] as int? ?? -1,
    message: json['message'] as String? ?? '',
    data: json['data'] == null ? null : fromJsonT(json['data']),
  );
}

/// HoYoLAB API クライアント（genshin_material 参考・自前実装）
class HoyolabApi {
  HoyolabApi({
    required this.cookie,
    this.region,
    this.uid,
    this.appVersion = HoyolabConstants.defaultAppVersion,
    http.Client? client,
    ApiRequestQueue? queue,
  }) : _client = client ?? http.Client(),
       _queue = queue ?? _sharedQueue;

  final String? cookie;
  final String? region;
  final String? uid;
  final String appVersion;
  final http.Client _client;
  final ApiRequestQueue _queue;

  static final _sharedQueue = ApiRequestQueue();
  static const _httpTimeout = Duration(seconds: 25);

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      _client.get(uri, headers: headers).timeout(_httpTimeout);

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => _client.post(uri, headers: headers, body: body).timeout(_httpTimeout);

  Future<List<HoyolabRegion>> lookupRegions() {
    return _queue.run(() async {
      final uri = Uri.parse(
        '${HoyolabConstants.getAllRegionsUrl}?game_biz=hk4e_global',
      );
      final response = await _get(uri);
      return _parseListResponse(response, HoyolabRegion.fromJson);
    });
  }

  Future<HoyolabUserInfo> verifyLToken() {
    _ensureCookie();
    return _queue.run(() async {
      final response = await _post(
        Uri.parse(HoyolabConstants.verifyLTokenUrl),
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
        ),
      );
      return _parseResponse(response, (obj) {
        final data = obj as Map<String, dynamic>;
        final userInfo = data['user_info'] as Map<String, dynamic>?;
        if (userInfo != null) {
          return HoyolabUserInfo.fromJson(userInfo);
        }
        return HoyolabUserInfo.fromJson(data);
      });
    });
  }

  Future<List<HoyolabGameRole>> getUserGameRoles({required String region}) {
    _ensureCookie();
    return _queue.run(() async {
      final uri = Uri.parse(
        '${HoyolabConstants.getUserGameRolesUrl}?game_biz=hk4e_global&region=$region',
      );
      final response = await _get(
        uri,
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
        ),
      );
      return _parseListResponse(
        response,
        (json) => HoyolabGameRole.fromJson(json, region: region),
      );
    });
  }

  Future<DailyNote> getDailyNote() {
    _ensureDailyNoteParams();
    final query = {'role_id': uid!, 'server': region!};
    return _queue.run(() async {
      final uri = Uri.parse(
        HoyolabConstants.dailyNoteUrl,
      ).replace(queryParameters: query);
      final ds = HoyolabAuth.generateDsToken(queryParameters: query);
      final response = await _get(
        uri,
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
          dsToken: ds,
        ),
      );
      return _parseResponse(
        response,
        (obj) => DailyNote.fromJson(obj! as Map<String, dynamic>),
      );
    });
  }

  Future<List<HoyolabOwnedCharacter>> getOwnedCharacters() {
    _ensureRecordParams();
    return _queue.run(() async {
      final bodyMap = _recordBody();
      final body = jsonEncode(bodyMap);
      final ds = HoyolabAuth.generateDsToken(body: body);
      final paths = [
        HoyolabConstants.characterListPath,
        HoyolabConstants.characterLegacyPath,
      ];

      HoyolabApiException? lastError;
      List<HoyolabOwnedCharacter>? fallbackWithoutRelics;
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        for (final path in paths) {
          try {
            final response = await _post(
              Uri.parse('$base$path'),
              headers: HoyolabAuth.buildRecordHeaders(
                cookie: cookie!,
                appVersion: appVersion,
                dsToken: ds,
                jsonBody: true,
              ),
              body: body,
            );
            final json = HoyolabHttpGuard.decodeJsonObject(response);
            final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
              json,
              (obj) => obj! as Map<String, dynamic>,
            );
            if (result.hasError) {
              throw HoyolabApiException(result.retcode, result.message);
            }
            final owned = _parseOwnedCharacterList(result.data ?? {});
            if (owned.isEmpty) continue;

            final relicCount = owned.fold<int>(
              0,
              (n, c) => n + c.relics.length,
            );
            // /character/list は聖遺物無しのことがある → レガシーを優先試行
            if (relicCount == 0 && path == HoyolabConstants.characterListPath) {
              fallbackWithoutRelics ??= owned;
              continue;
            }
            return owned;
          } on HoyolabApiException catch (e) {
            lastError = e;
          } on HoyolabHttpException {
            continue;
          }
        }
      }

      if (fallbackWithoutRelics != null) return fallbackWithoutRelics;
      if (lastError != null) throw lastError;
      throw const HoyolabApiException(-1, '所持キャラクターを取得できませんでした');
    });
  }

  Future<HoyolabCharacterBuild?> getCharacterBuild(String characterId) async {
    final list = await getCharacterBuilds([characterId]);
    return list.isEmpty ? null : list.first;
  }

  /// `/character/detail` で複数キャラの装備（聖遺物含む）を取得する。
  /// 現代 API では `/character/list` に聖遺物が載らないため、装備集計の正本。
  Future<List<HoyolabCharacterBuild>> getCharacterBuilds(
    List<String> characterIds, {
    int batchSize = HoyolabConstants.characterDetailBatchSize,
  }) {
    _ensureRecordParams();
    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in characterIds) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      uniqueIds.add(trimmed);
    }
    if (uniqueIds.isEmpty) return Future.value(const []);

    return _queue.run(() async {
      final out = <HoyolabCharacterBuild>[];
      final size = batchSize < 1 ? uniqueIds.length : batchSize;
      for (var i = 0; i < uniqueIds.length; i += size) {
        final end = (i + size > uniqueIds.length) ? uniqueIds.length : i + size;
        final chunk = uniqueIds.sublist(i, end);
        out.addAll(await _fetchCharacterBuildChunk(chunk));
      }
      return out;
    });
  }

  Future<List<HoyolabCharacterBuild>> _fetchCharacterBuildChunk(
    List<String> characterIds,
  ) async {
    final bodyMap = {
      ..._recordBody(),
      'character_ids': [for (final id in characterIds) _parseCharacterId(id)],
    };
    final body = jsonEncode(bodyMap);
    final ds = HoyolabAuth.generateDsToken(body: body);

    HoyolabApiException? lastError;
    for (final base in HoyolabConstants.gameRecordBaseUrls) {
      try {
        final response = await _post(
          Uri.parse('$base${HoyolabConstants.characterDetailPath}'),
          headers: HoyolabAuth.buildRecordHeaders(
            cookie: cookie!,
            appVersion: appVersion,
            dsToken: ds,
            jsonBody: true,
          ),
          body: body,
        );
        final json = HoyolabHttpGuard.decodeJsonObject(response);
        final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
          json,
          (obj) => obj! as Map<String, dynamic>,
        );
        if (result.hasError) {
          throw HoyolabApiException(result.retcode, result.message);
        }
        final data = result.data ?? {};
        final list = data['list'] as List<dynamic>? ?? [];
        final propertyMap = parseGameRecordPropertyMap(data['property_map']);
        return [
          for (final raw in list)
            HoyolabCharacterBuild.fromDetailJson(
              raw as Map<String, dynamic>,
              propertyMap: propertyMap,
            ),
        ];
      } on HoyolabApiException catch (e) {
        lastError = e;
      } on HoyolabHttpException {
        continue;
      }
    }

    if (lastError != null) throw lastError;
    return const [];
  }

  Future<SpiralAbyssStatus> getSpiralAbyss({int scheduleType = 1}) {
    _ensureRecordParams();
    return _queue.run(() async {
      final query = {
        'role_id': uid!,
        'server': region!,
        'schedule_type': '$scheduleType',
      };
      final ds = HoyolabAuth.generateDsToken(queryParameters: query);

      HoyolabApiException? lastError;
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        try {
          final uri = Uri.parse(
            '$base${HoyolabConstants.spiralAbyssPath}',
          ).replace(queryParameters: query);
          final response = await _get(
            uri,
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
            ),
          );
          return _parseResponse(
            response,
            (obj) => SpiralAbyssStatus.fromJson(obj! as Map<String, dynamic>),
          );
        } on HoyolabApiException catch (e) {
          lastError = e;
        } on HoyolabHttpException {
          continue;
        } on HoyolabHttpException {
          continue;
        }
      }

      if (lastError != null) throw lastError;
      throw const HoyolabApiException(-1, '深境螺旋データを取得できませんでした');
    });
  }

  Future<ImaginariumTheaterStatus?> getImaginariumTheater({
    bool needDetail = true,
  }) {
    _ensureRecordParams();
    return _queue.run(() async {
      final query = {
        'role_id': uid!,
        'server': region!,
        'need_detail': needDetail ? 'true' : 'false',
      };
      final ds = HoyolabAuth.generateDsToken(queryParameters: query);

      HoyolabApiException? lastError;
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        try {
          final uri = Uri.parse(
            '$base${HoyolabConstants.roleCombatPath}',
          ).replace(queryParameters: query);
          final response = await _get(
            uri,
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
            ),
          );
          final json = HoyolabHttpGuard.decodeJsonObject(response);
          final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
            json,
            (obj) => obj! as Map<String, dynamic>,
          );
          if (result.hasError) {
            throw HoyolabApiException(result.retcode, result.message);
          }
          final data = result.data;
          if (data == null) return null;
          final seasons = data['data'] as List<dynamic>? ?? [];
          if (seasons.isEmpty) {
            return ImaginariumTheaterStatus(
              isUnlocked: data['is_unlock'] as bool? ?? false,
              difficultyId: 0,
              maxRoundId: 0,
              medalNum: 0,
              hasData: false,
            );
          }
          return ImaginariumTheaterStatus.fromSeasonJson(
            seasons.first as Map<String, dynamic>,
          );
        } on HoyolabApiException catch (e) {
          lastError = e;
        } on HoyolabHttpException {
          continue;
        }
      }

      if (lastError != null) throw lastError;
      return null;
    });
  }

  Future<StygianOnslaughtStatus?> getStygianOnslaught({
    bool needDetail = true,
  }) {
    _ensureRecordParams();
    return _queue.run(() async {
      final query = {
        'role_id': uid!,
        'server': region!,
        'need_detail': needDetail ? 'true' : 'false',
      };
      final ds = HoyolabAuth.generateDsToken(queryParameters: query);

      HoyolabApiException? lastError;
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        try {
          final uri = Uri.parse(
            '$base${HoyolabConstants.hardChallengePath}',
          ).replace(queryParameters: query);
          final response = await _get(
            uri,
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
            ),
          );
          final json = HoyolabHttpGuard.decodeJsonObject(response);
          final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
            json,
            (obj) => obj! as Map<String, dynamic>,
          );
          if (result.hasError) {
            throw HoyolabApiException(result.retcode, result.message);
          }
          final data = result.data;
          if (data == null) return null;

          final seasons = data['data'] as List<dynamic>? ?? [];
          for (final raw in seasons) {
            final item = raw as Map<String, dynamic>;
            final schedule = item['schedule'] as Map<String, dynamic>? ?? {};
            if (schedule['is_valid'] as bool? ?? false) {
              return StygianOnslaughtStatus.fromSeasonJson(item);
            }
          }

          if (seasons.isEmpty) {
            return StygianOnslaughtStatus(
              isUnlocked: data['is_unlock'] as bool? ?? false,
              bestDifficultyId: 0,
              bestTimeSeconds: 0,
              hasData: false,
            );
          }

          return StygianOnslaughtStatus.fromSeasonJson(
            seasons.first as Map<String, dynamic>,
          );
        } on HoyolabApiException catch (e) {
          lastError = e;
        } on HoyolabHttpException {
          continue;
        }
      }

      if (lastError != null) throw lastError;
      return null;
    });
  }

  Future<AdventureStatus> getAdventureStatus() async {
    SpiralAbyssStatus? spiral;
    ImaginariumTheaterStatus? theater;
    StygianOnslaughtStatus? stygian;
    try {
      spiral = await getSpiralAbyss();
    } on HoyolabApiException {
      spiral = null;
    }
    try {
      theater = await getImaginariumTheater();
    } on HoyolabApiException {
      theater = null;
    }
    try {
      stygian = await getStygianOnslaught();
    } on HoyolabApiException {
      stygian = null;
    }
    return AdventureStatus(
      spiralAbyss: spiral,
      imaginariumTheater: theater,
      stygianOnslaught: stygian,
      fetchedAt: DateTime.now(),
    );
  }

  T _parseResponse<T>(
    http.Response response,
    T Function(Object? obj) fromJsonT,
  ) {
    return _parseMap(HoyolabHttpGuard.decodeJsonObject(response), fromJsonT);
  }

  List<T> _parseListResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic> json) fromJsonItem,
  ) {
    return _parseListMap(
      HoyolabHttpGuard.decodeJsonObject(response),
      fromJsonItem,
    );
  }

  T _parseMap<T>(Map<String, dynamic> json, T Function(Object? obj) fromJsonT) {
    final result = HoyolabApiResult<T>.fromJson(json, fromJsonT);
    if (result.hasError) {
      throw HoyolabApiException(result.retcode, result.message);
    }
    if (result.data == null) {
      throw const HoyolabApiException(-1, 'empty data');
    }
    return result.data as T;
  }

  List<T> _parseListMap<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) fromJsonItem,
  ) {
    final result = HoyolabApiResult<List<T>>.fromJson(json, (obj) {
      final data = obj as Map<String, dynamic>;
      final list = data['list'] as List<dynamic>? ?? [];
      return list.map((e) => fromJsonItem(e as Map<String, dynamic>)).toList();
    });
    if (result.hasError) {
      throw HoyolabApiException(result.retcode, result.message);
    }
    return result.data ?? [];
  }

  void _ensureCookie() {
    if (cookie == null || cookie!.isEmpty) {
      throw StateError('Missing cookie');
    }
  }

  void _ensureDailyNoteParams() {
    _ensureCookie();
    if (uid == null || uid!.isEmpty) {
      throw StateError('Missing uid');
    }
    if (region == null || region!.isEmpty) {
      throw StateError('Missing region');
    }
  }

  void _ensureRecordParams() => _ensureDailyNoteParams();

  Map<String, Object> _recordBody() => {
    'role_id': int.tryParse(uid!) ?? 0,
    'server': region!,
  };

  List<HoyolabOwnedCharacter> _parseOwnedCharacterList(
    Map<String, dynamic> data,
  ) {
    final list =
        data['list'] as List<dynamic>? ??
        data['avatars'] as List<dynamic>? ??
        [];
    return list
        .map(
          (e) =>
              HoyolabOwnedCharacter.fromSummaryJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  static int _parseCharacterId(String id) {
    final base = id.split('-').first;
    return int.tryParse(base) ?? int.tryParse(id) ?? 0;
  }
}
