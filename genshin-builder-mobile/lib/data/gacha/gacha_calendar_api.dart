import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/gacha/calendar_event.dart';
import '../../domain/gacha/gacha_banner.dart';

class GenshinCalendarSnapshot {
  const GenshinCalendarSnapshot({
    required this.banners,
    required this.events,
    required this.fetchedAt,
  });

  final List<GachaBanner> banners;
  final List<CalendarEvent> events;
  final DateTime fetchedAt;
}

/// HoYoverse カレンダー（ennead 経由）から現行バナー・イベントを取得
class GachaCalendarApi {
  GachaCalendarApi({
    http.Client? client,
    this.baseUrl = 'https://api.ennead.cc/mihoyo/genshin/calendar',
    this.lang = 'ja-jp',
    this.timeout = const Duration(seconds: 15),
    this.cacheTtl = const Duration(minutes: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String lang;
  final Duration timeout;
  final Duration cacheTtl;

  GenshinCalendarSnapshot? _cache;

  Future<GenshinCalendarSnapshot> fetchCalendar({
    bool forceRefresh = false,
  }) async {
    final cached = _cache;
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return cached;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: {'lang': lang});
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('gacha calendar error: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final bannersRaw = json['banners'] as List<dynamic>? ?? const [];
    final eventsRaw = json['events'] as List<dynamic>? ?? const [];
    final snap = GenshinCalendarSnapshot(
      banners: [
        for (final item in bannersRaw)
          if (item is Map<String, dynamic>) parseCalendarBanner(item),
      ],
      events: [
        for (final item in eventsRaw)
          if (item is Map<String, dynamic>) parseCalendarEvent(item),
      ],
      fetchedAt: DateTime.now(),
    );
    _cache = snap;
    return snap;
  }

  Future<List<GachaBanner>> fetchCurrentBanners({
    bool forceRefresh = false,
  }) async {
    final snap = await fetchCalendar(forceRefresh: forceRefresh);
    return snap.banners;
  }

  Future<List<CalendarEvent>> fetchCurrentEvents({
    bool forceRefresh = false,
  }) async {
    final snap = await fetchCalendar(forceRefresh: forceRefresh);
    return snap.events;
  }

  void dispose() {
    _client.close();
    _cache = null;
  }
}

CalendarEvent parseCalendarEvent(Map<String, dynamic> json) {
  final startSec = (json['start_time'] as num?)?.toInt() ?? 0;
  final endSec = (json['end_time'] as num?)?.toInt() ?? 0;
  final image = '${json['image_url'] ?? ''}'.trim();
  return CalendarEvent(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}'.trim(),
    description: '${json['description'] ?? ''}'.trim(),
    typeName: '${json['type_name'] ?? ''}'.trim(),
    start: DateTime.fromMillisecondsSinceEpoch(startSec * 1000, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(endSec * 1000, isUtc: true),
    imageUrl: image.isEmpty ? null : image,
    rewards: [
      for (final r in json['rewards'] as List<dynamic>? ?? const [])
        if (r is Map<String, dynamic>) parseCalendarEventReward(r),
    ],
    specialReward: json['special_reward'] is Map<String, dynamic>
        ? parseCalendarEventReward(
            json['special_reward'] as Map<String, dynamic>,
          )
        : null,
  );
}

CalendarEventReward parseCalendarEventReward(Map<String, dynamic> json) {
  final icon = '${json['icon'] ?? ''}'.trim();
  return CalendarEventReward(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}'.trim(),
    icon: icon.isEmpty ? null : icon,
    rarity: json['rarity']?.toString(),
    amount: (json['amount'] as num?)?.toInt(),
  );
}

GachaBanner parseCalendarBanner(Map<String, dynamic> json) {
  final name = '${json['name'] ?? ''}'.trim();
  final type = inferBannerTypeFromName(name);
  final startSec = (json['start_time'] as num?)?.toInt() ?? 0;
  final endSec = (json['end_time'] as num?)?.toInt() ?? 0;
  final id = 'live-${json['id'] ?? '${type.name}-$startSec'}';

  final featured5 = <String>[];
  final featured4 = <String>[];
  final weapons = <String>[];
  final icons = <String, String>{};

  void ingestCharacter(Map<String, dynamic> c) {
    final cid = '${c['id'] ?? ''}'.trim();
    if (cid.isEmpty || cid == '0') return;
    final rarity = (c['rarity'] as num?)?.toInt() ?? 0;
    final icon = '${c['icon'] ?? ''}'.trim();
    if (icon.isNotEmpty) icons[cid] = icon;
    if (rarity >= 5) {
      featured5.add(cid);
    } else {
      featured4.add(cid);
    }
  }

  void ingestWeapon(Map<String, dynamic> w) {
    final wid = '${w['id'] ?? ''}'.trim();
    if (wid.isEmpty || wid == '0') return;
    final icon = '${w['icon'] ?? ''}'.trim();
    if (icon.isNotEmpty) icons[wid] = icon;
    weapons.add(wid);
  }

  for (final c in json['characters'] as List<dynamic>? ?? const []) {
    if (c is Map<String, dynamic>) ingestCharacter(c);
  }
  for (final w in json['weapons'] as List<dynamic>? ?? const []) {
    if (w is Map<String, dynamic>) ingestWeapon(w);
  }

  return GachaBanner(
    id: id,
    type: type,
    name: name.isEmpty ? gachaBannerTypeLabel(type) : name,
    version: '${json['version'] ?? ''}'.trim(),
    start: DateTime.fromMillisecondsSinceEpoch(startSec * 1000, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(endSec * 1000, isUtc: true),
    featured5Ids: featured5,
    featured4Ids: featured4,
    featuredWeaponIds: weapons,
    sourceIcons: icons,
  );
}

GachaBannerType inferBannerTypeFromName(String name) {
  final n = name.toLowerCase();
  if (n.contains('集録') ||
      n.contains('追憶') ||
      n.contains('chronicled')) {
    return GachaBannerType.chronicled;
  }
  if (n.contains('武器') || n.contains('weapon') || n.contains('神鋳')) {
    return GachaBannerType.weapon;
  }
  if (n.contains('祈願2') ||
      n.contains('キャラクター祈願2') ||
      n.contains('event wish - 2') ||
      RegExp(r'2\s*$').hasMatch(name.trim())) {
    return GachaBannerType.character2;
  }
  return GachaBannerType.character;
}
