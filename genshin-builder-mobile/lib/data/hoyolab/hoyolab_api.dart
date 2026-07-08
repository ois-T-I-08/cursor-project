import 'dart:convert';

import 'package:http/http.dart' as http;

import 'hoyolab_auth.dart';
import 'hoyolab_constants.dart';
import 'hoyolab_exceptions.dart';
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
  ) =>
      HoyolabApiResult(
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
  })  : _client = client ?? http.Client(),
        _queue = queue ?? _sharedQueue;

  final String? cookie;
  final String? region;
  final String? uid;
  final String appVersion;
  final http.Client _client;
  final ApiRequestQueue _queue;

  static final _sharedQueue = ApiRequestQueue();

  Future<List<HoyolabRegion>> lookupRegions() {
    return _queue.run(() async {
      final uri = Uri.parse(
        '${HoyolabConstants.getAllRegionsUrl}?game_biz=hk4e_global',
      );
      final response = await _client.get(uri);
      return _parseList(
        response.body,
        HoyolabRegion.fromJson,
      );
    });
  }

  Future<HoyolabUserInfo> verifyLToken() {
    _ensureCookie();
    return _queue.run(() async {
      final response = await _client.post(
        Uri.parse(HoyolabConstants.verifyLTokenUrl),
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
        ),
      );
      return _parse(
        response.body,
        (obj) {
          final data = obj as Map<String, dynamic>;
          final userInfo = data['user_info'] as Map<String, dynamic>?;
          if (userInfo != null) {
            return HoyolabUserInfo.fromJson(userInfo);
          }
          return HoyolabUserInfo.fromJson(data);
        },
      );
    });
  }

  Future<List<HoyolabGameRole>> getUserGameRoles({required String region}) {
    _ensureCookie();
    return _queue.run(() async {
      final uri = Uri.parse(
        '${HoyolabConstants.getUserGameRolesUrl}?game_biz=hk4e_global&region=$region',
      );
      final response = await _client.get(
        uri,
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
        ),
      );
      return _parseList(
        response.body,
        (json) => HoyolabGameRole.fromJson(json, region: region),
      );
    });
  }

  Future<DailyNote> getDailyNote() {
    _ensureDailyNoteParams();
    final query = {
      'role_id': uid!,
      'server': region!,
    };
    return _queue.run(() async {
      final uri = Uri.parse(HoyolabConstants.dailyNoteUrl)
          .replace(queryParameters: query);
      final ds = HoyolabAuth.generateDsToken(queryParameters: query);
      final response = await _client.get(
        uri,
        headers: HoyolabAuth.buildHeaders(
          cookie: cookie!,
          appVersion: appVersion,
          dsToken: ds,
        ),
      );
      return _parse(
        response.body,
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
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        for (final path in paths) {
          try {
            final response = await _client.post(
              Uri.parse('$base$path'),
              headers: HoyolabAuth.buildRecordHeaders(
                cookie: cookie!,
                appVersion: appVersion,
                dsToken: ds,
                jsonBody: true,
              ),
              body: body,
            );
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
              json,
              (obj) => obj! as Map<String, dynamic>,
            );
            if (result.hasError) {
              throw HoyolabApiException(result.retcode, result.message);
            }
            final owned = _parseOwnedCharacterList(result.data ?? {});
            if (owned.isNotEmpty || path == HoyolabConstants.characterListPath) {
              return owned;
            }
          } on HoyolabApiException catch (e) {
            lastError = e;
          }
        }
      }

      if (lastError != null) throw lastError;
      throw const HoyolabApiException(-1, '所持キャラクターを取得できませんでした');
    });
  }

  Future<HoyolabCharacterBuild?> getCharacterBuild(String characterId) {
    _ensureRecordParams();
    return _queue.run(() async {
      final bodyMap = {
        ..._recordBody(),
        'character_ids': [_parseCharacterId(characterId)],
      };
      final body = jsonEncode(bodyMap);
      final ds = HoyolabAuth.generateDsToken(body: body);

      HoyolabApiException? lastError;
      for (final base in HoyolabConstants.gameRecordBaseUrls) {
        try {
          final response = await _client.post(
            Uri.parse('$base${HoyolabConstants.characterDetailPath}'),
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
              jsonBody: true,
            ),
            body: body,
          );
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final result = HoyolabApiResult<Map<String, dynamic>>.fromJson(
            json,
            (obj) => obj! as Map<String, dynamic>,
          );
          if (result.hasError) {
            throw HoyolabApiException(result.retcode, result.message);
          }
          final data = result.data ?? {};
          final list = data['list'] as List<dynamic>? ?? [];
          if (list.isEmpty) return null;
          return HoyolabCharacterBuild.fromDetailJson(
            list.first as Map<String, dynamic>,
          );
        } on HoyolabApiException catch (e) {
          lastError = e;
        }
      }

      if (lastError != null) throw lastError;
      return null;
    });
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
          final uri = Uri.parse('$base${HoyolabConstants.spiralAbyssPath}')
              .replace(queryParameters: query);
          final response = await _client.get(
            uri,
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
            ),
          );
          return _parse(
            response.body,
            (obj) => SpiralAbyssStatus.fromJson(obj! as Map<String, dynamic>),
          );
        } on HoyolabApiException catch (e) {
          lastError = e;
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
          final uri = Uri.parse('$base${HoyolabConstants.roleCombatPath}')
              .replace(queryParameters: query);
          final response = await _client.get(
            uri,
            headers: HoyolabAuth.buildRecordHeaders(
              cookie: cookie!,
              appVersion: appVersion,
              dsToken: ds,
            ),
          );
          final json = jsonDecode(response.body) as Map<String, dynamic>;
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
        }
      }

      if (lastError != null) throw lastError;
      return null;
    });
  }

  Future<AdventureStatus> getAdventureStatus() async {
    SpiralAbyssStatus? spiral;
    ImaginariumTheaterStatus? theater;
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
    return AdventureStatus(
      spiralAbyss: spiral,
      imaginariumTheater: theater,
      fetchedAt: DateTime.now(),
    );
  }

  T _parse<T>(String body, T Function(Object? obj) fromJsonT) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = HoyolabApiResult<T>.fromJson(json, fromJsonT);
    if (result.hasError) {
      throw HoyolabApiException(result.retcode, result.message);
    }
    if (result.data == null) {
      throw const HoyolabApiException(-1, 'empty data');
    }
    return result.data as T;
  }

  List<T> _parseList<T>(
    String body,
    T Function(Map<String, dynamic> json) fromJsonItem,
  ) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = HoyolabApiResult<List<T>>.fromJson(
      json,
      (obj) {
        final data = obj as Map<String, dynamic>;
        final list = data['list'] as List<dynamic>? ?? [];
        return list
            .map((e) => fromJsonItem(e as Map<String, dynamic>))
            .toList();
      },
    );
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
    final list = data['list'] as List<dynamic>? ??
        data['avatars'] as List<dynamic>? ??
        [];
    return list
        .map(
          (e) => HoyolabOwnedCharacter.fromSummaryJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  static int _parseCharacterId(String id) {
    final base = id.split('-').first;
    return int.tryParse(base) ?? int.tryParse(id) ?? 0;
  }
}
