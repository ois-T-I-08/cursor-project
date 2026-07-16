import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../domain/gacha/calendar_event.dart';
import '../../domain/planning/ley_line_overflow.dart';
import '../../domain/planning/ley_line_overflow_catalog.dart';
import '../../domain/planning/ley_line_overflow_resolve.dart';
import '../config/config_load_log.dart';
import '../config/config_validators.dart';
import '../gacha/gacha_calendar_api.dart';

const _configKind = 'ley_line_overflow_events';

abstract class LeyLineOverflowCatalogSource {
  Future<LeyLineOverflowCatalog> load();
}

class LocalJsonLeyLineOverflowCatalogSource
    implements LeyLineOverflowCatalogSource {
  LocalJsonLeyLineOverflowCatalogSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/config/ley_line_overflow_events.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  LeyLineOverflowCatalog? _cache;

  @override
  Future<LeyLineOverflowCatalog> load() async {
    if (_cache != null) return _cache!;
    late final String raw;
    try {
      raw = await _bundle.loadString(assetPath);
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.assetMissing,
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.invalidJson,
      );
    }
    if (decoded is! Map) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.invalidRootType,
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    try {
      validateLeyLineOverflowEventsJson(map);
    } on FormatException catch (e) {
      throw configLoadFromFormatException(kind: _configKind, error: e);
    }
    try {
      _cache = LeyLineOverflowCatalog.fromJson(map);
      return _cache!;
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
  }
}

class RemoteLeyLineOverflowCatalogSource
    implements LeyLineOverflowCatalogSource {
  RemoteLeyLineOverflowCatalogSource({
    required this.url,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String url;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<LeyLineOverflowCatalog> load() async {
    final response = await _client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('ley_line_overflow remote HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('ley_line_overflow remote: root must be object');
    }
    final map = Map<String, dynamic>.from(decoded);
    validateLeyLineOverflowEventsJson(map);
    return LeyLineOverflowCatalog.fromJson(map);
  }
}

class CompositeLeyLineOverflowCatalogSource
    implements LeyLineOverflowCatalogSource {
  CompositeLeyLineOverflowCatalogSource({
    required LeyLineOverflowCatalogSource localSource,
    LeyLineOverflowCatalogSource? remoteSource,
  })  : _local = localSource,
        _remote = remoteSource;

  final LeyLineOverflowCatalogSource _local;
  final LeyLineOverflowCatalogSource? _remote;

  @override
  Future<LeyLineOverflowCatalog> load() async {
    final local = await _local.load();
    final remote = _remote;
    if (remote == null) return local;
    try {
      final remoteCatalog = await remote.load();
      if (remoteCatalog.version >= local.version) return remoteCatalog;
    } catch (e) {
      logRemoteFallback(kind: _configKind, error: e);
    }
    return local;
  }
}

class LeyLineOverflowRepository {
  LeyLineOverflowRepository({
    required LeyLineOverflowCatalogSource catalogSource,
    GachaCalendarApi? calendarApi,
    Clock? clock,
    this.bonusUsedTodayProvider,
  })  : _catalogSource = catalogSource,
        _calendarApi = calendarApi,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final LeyLineOverflowCatalogSource _catalogSource;
  final GachaCalendarApi? _calendarApi;
  final Clock _clock;

  /// 当日のボーナス使用済み回数。取得不可なら null。
  final Future<int?> Function()? bonusUsedTodayProvider;

  Future<LeyLineOverflowStatus> resolveStatus({
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? _clock()).toUtc();
    LeyLineOverflowCatalog catalog;
    try {
      catalog = await _catalogSource.load();
    } catch (_) {
      return const LeyLineOverflowStatus(
        isActive: false,
        resolveFailed: true,
      );
    }

    List<CalendarEvent> calendarEvents = const [];
    final api = _calendarApi;
    if (api != null) {
      try {
        calendarEvents = await api.fetchCurrentEvents();
      } catch (_) {
        // カレンダー失敗時は設定フォールバックのみ（誤って開催中にしない）
        calendarEvents = const [];
      }
    }

    int? used;
    final usedProvider = bonusUsedTodayProvider;
    if (usedProvider != null) {
      try {
        used = await usedProvider();
      } catch (_) {
        used = null;
      }
    }

    return resolveLeyLineOverflowStatus(
      catalog: catalog,
      nowUtc: now,
      calendarEvents: calendarEvents,
      bonusUsedToday: used,
    );
  }
}
