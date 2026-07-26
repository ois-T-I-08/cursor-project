import '../planning/ley_line_overflow.dart';

/// ローカル / リモート JSON の正本（開催スケジュール＋マッチャ）。
class LeyLineOverflowCatalog {
  const LeyLineOverflowCatalog({
    required this.version,
    required this.defaults,
    this.events = const [],
  });

  final int version;
  final LeyLineOverflowDefaults defaults;
  final List<LeyLineOverflowEvent> events;

  factory LeyLineOverflowCatalog.fromJson(Map<String, dynamic> json) {
    final defaultsRaw = Map<String, dynamic>.from(json['defaults'] as Map);
    final defaults = LeyLineOverflowDefaults.fromJson(defaultsRaw);
    final eventsRaw = json['events'] as List? ?? const [];
    final events = <LeyLineOverflowEvent>[];
    for (final e in eventsRaw) {
      if (e is! Map) continue;
      final event = LeyLineOverflowEventFromJson.parse(
        Map<String, dynamic>.from(e),
        defaults: defaults,
        sourceFallback: 'config',
      );
      if (event != null) events.add(event);
    }
    return LeyLineOverflowCatalog(
      version: (json['version'] as num).toInt(),
      defaults: defaults,
      events: events,
    );
  }
}

class LeyLineOverflowDefaults {
  const LeyLineOverflowDefaults({
    required this.displayName,
    required this.dailyBonusLimit,
    required this.nameMatchers,
    this.eventType = 'leyLineOverflow',
    this.rewardMultiplier = 2,
    this.condensedResinEligible = false,
    this.eligibleLeyLineTypes = const [
      LeyLineOverflowLeyLineType.exp,
      LeyLineOverflowLeyLineType.mora,
    ],
  });

  final String displayName;
  final String eventType;
  final int dailyBonusLimit;
  final int rewardMultiplier;

  /// 常に false（地脈の奔流は濃縮樹脂対象外）。
  final bool condensedResinEligible;
  final List<LeyLineOverflowLeyLineType> eligibleLeyLineTypes;
  final List<String> nameMatchers;

  factory LeyLineOverflowDefaults.fromJson(Map<String, dynamic> json) {
    final matchers = <String>[
      for (final m in json['nameMatchers'] as List? ?? const [])
        if ('$m'.trim().isNotEmpty) '$m'.trim(),
    ];
    final multiplier = (json['rewardMultiplier'] as num?)?.toInt() ?? 2;
    return LeyLineOverflowDefaults(
      displayName: '${json['displayName'] ?? '地脈の奔流'}'.trim(),
      eventType: '${json['eventType'] ?? 'leyLineOverflow'}'.trim(),
      dailyBonusLimit: (json['dailyBonusLimit'] as num?)?.toInt() ?? 3,
      rewardMultiplier: multiplier < 2 ? 2 : multiplier,
      condensedResinEligible: false,
      eligibleLeyLineTypes: parseEligibleLeyLineTypes(
        json['eligibleLeyLineTypes'],
      ),
      nameMatchers: matchers.isEmpty ? const ['地脈の奔流'] : matchers,
    );
  }

  bool matchesEventName(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    for (final m in nameMatchers) {
      if (n.contains(m)) return true;
    }
    return false;
  }
}

/// JSON → [LeyLineOverflowEvent]
class LeyLineOverflowEventFromJson {
  static LeyLineOverflowEvent? parse(
    Map<String, dynamic> json, {
    required LeyLineOverflowDefaults defaults,
    String sourceFallback = 'config',
  }) {
    final id = '${json['eventId'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final start = _parseDate(json['startAt']);
    final end = _parseDate(json['endAt']);
    if (start == null || end == null) return null;
    if (!end.isAfter(start) && end != start) {
      // allow equal only if zero-length disabled
    }
    if (end.isBefore(start)) return null;

    final rawName = '${json['displayName'] ?? defaults.displayName}'.trim();
    final multiplier = (json['rewardMultiplier'] as num?)?.toInt() ??
        defaults.rewardMultiplier;
    if (multiplier < 2) return null;
    final limit =
        (json['dailyBonusLimit'] as num?)?.toInt() ?? defaults.dailyBonusLimit;
    if (limit < 0) return null;

    return LeyLineOverflowEvent(
      eventId: id,
      eventType: '${json['eventType'] ?? defaults.eventType}'.trim(),
      displayName: rawName.isEmpty ? defaults.displayName : rawName,
      startAt: start,
      endAt: end,
      dailyBonusLimit: limit,
      rewardMultiplier: multiplier,
      condensedResinEligible: false,
      eligibleLeyLineTypes: json.containsKey('eligibleLeyLineTypes')
          ? parseEligibleLeyLineTypes(json['eligibleLeyLineTypes'])
          : defaults.eligibleLeyLineTypes,
      enabled: json['enabled'] as bool? ?? true,
      source: '${json['source'] ?? sourceFallback}'.trim(),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      // unix seconds or ms
      final n = raw.toInt();
      if (n > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    }
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    return parsed?.toUtc();
  }
}
