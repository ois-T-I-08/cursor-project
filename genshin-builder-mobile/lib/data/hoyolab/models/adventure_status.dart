class SpiralAbyssStatus {
  const SpiralAbyssStatus({
    required this.maxFloor,
    required this.totalStars,
    required this.isUnlocked,
    this.scheduleId,
    this.updatedAt,
  });

  final String maxFloor;
  final int totalStars;
  final bool isUnlocked;
  final int? scheduleId;
  final DateTime? updatedAt;

  factory SpiralAbyssStatus.fromJson(Map<String, dynamic> json) {
    final cachedAt = json['updated_at'] as String?;
    if (cachedAt != null) {
      return SpiralAbyssStatus(
        maxFloor: json['max_floor'] as String? ?? '-',
        totalStars: _asInt(json['total_star']),
        isUnlocked: json['is_unlock'] as bool? ?? false,
        scheduleId:
            json['schedule_id'] == null ? null : _asInt(json['schedule_id']),
        updatedAt: DateTime.tryParse(cachedAt),
      );
    }

    final start = int.tryParse('${json['start_time'] ?? ''}');
    return SpiralAbyssStatus(
      maxFloor: json['max_floor'] as String? ?? '-',
      totalStars: _asInt(json['total_star']),
      isUnlocked: json['is_unlock'] as bool? ?? false,
      scheduleId: _asInt(json['schedule_id']),
      updatedAt:
          start == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(start * 1000),
    );
  }

  Map<String, dynamic> toJson() => {
    'max_floor': maxFloor,
    'total_star': totalStars,
    'is_unlock': isUnlocked,
    if (scheduleId != null) 'schedule_id': scheduleId,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class ImaginariumTheaterStatus {
  const ImaginariumTheaterStatus({
    required this.isUnlocked,
    required this.difficultyId,
    required this.maxRoundId,
    required this.medalNum,
    this.hasData = false,
    this.updatedAt,
    this.highlightAvatars = const [],
  });

  final bool isUnlocked;
  final int difficultyId;
  final int maxRoundId;
  final int medalNum;
  final bool hasData;
  final DateTime? updatedAt;
  final List<String> highlightAvatars;

  String get difficultyLabel => switch (difficultyId) {
    1 => 'イージー',
    2 => 'ノーマル',
    3 => 'ハード',
    4 => 'エキスパート',
    5 => 'アルカナ',
    _ => '難易度 $difficultyId',
  };

  factory ImaginariumTheaterStatus.fromSeasonJson(Map<String, dynamic> json) {
    final stat = json['stat'] as Map<String, dynamic>? ?? {};
    final schedule = json['schedule'] as Map<String, dynamic>? ?? {};
    final detail = json['detail'] as Map<String, dynamic>?;
    final avatars = <String>[];
    final rounds = detail?['rounds_data'] as List<dynamic>? ?? [];
    for (final round in rounds.take(2)) {
      final list =
          (round as Map<String, dynamic>)['avatars'] as List<dynamic>? ?? [];
      for (final avatar in list.take(4)) {
        final icon = (avatar as Map<String, dynamic>)['icon'] as String?;
        if (icon != null) avatars.add(icon);
      }
    }

    DateTime? updatedAt;
    final end = schedule['end_date_time'] as Map<String, dynamic>?;
    if (end != null) {
      updatedAt = DateTime(
        _asInt(end['year'], fallback: 1970),
        _asInt(end['month'], fallback: 1),
        _asInt(end['day'], fallback: 1),
      );
    }

    return ImaginariumTheaterStatus(
      isUnlocked: json['is_unlock'] as bool? ?? true,
      difficultyId: _asInt(stat['difficulty_id'], fallback: 1),
      maxRoundId: _asInt(stat['max_round_id']),
      medalNum: _asInt(stat['medal_num']),
      hasData: json['has_data'] as bool? ?? stat.isNotEmpty,
      updatedAt: updatedAt,
      highlightAvatars: avatars,
    );
  }

  factory ImaginariumTheaterStatus.fromCacheJson(Map<String, dynamic> json) =>
      ImaginariumTheaterStatus(
        isUnlocked: json['is_unlock'] as bool? ?? true,
        difficultyId: _asInt(json['difficulty_id'], fallback: 1),
        maxRoundId: _asInt(json['max_round_id']),
        medalNum: _asInt(json['medal_num']),
        hasData: json['has_data'] as bool? ?? false,
        updatedAt:
            json['updated_at'] == null
                ? null
                : DateTime.tryParse(json['updated_at'] as String),
        highlightAvatars: (json['highlight_avatars'] as List<dynamic>? ?? [])
            .map((e) => '$e')
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'is_unlock': isUnlocked,
    'difficulty_id': difficultyId,
    'max_round_id': maxRoundId,
    'medal_num': medalNum,
    'has_data': hasData,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    'highlight_avatars': highlightAvatars,
  };
}

class StygianOnslaughtStatus {
  const StygianOnslaughtStatus({
    required this.isUnlocked,
    required this.bestDifficultyId,
    required this.bestTimeSeconds,
    this.hasData = false,
    this.seasonName = '',
    this.updatedAt,
  });

  final bool isUnlocked;
  final int bestDifficultyId;
  final int bestTimeSeconds;
  final bool hasData;
  final String seasonName;
  final DateTime? updatedAt;

  String get difficultyLabel => switch (bestDifficultyId) {
    1 => 'イージー',
    2 => 'ノーマル',
    3 => 'ハード',
    4 => 'マスター',
    5 => 'エクストラ',
    6 => 'アルティメット',
    _ => bestDifficultyId > 0 ? '難易度 $bestDifficultyId' : '未挑戦',
  };

  factory StygianOnslaughtStatus.fromSeasonJson(Map<String, dynamic> json) {
    final schedule = json['schedule'] as Map<String, dynamic>? ?? {};
    final single = json['single'] as Map<String, dynamic>? ?? {};
    final best = single['best'] as Map<String, dynamic>?;

    DateTime? updatedAt;
    final end = schedule['end_date_time'] as Map<String, dynamic>?;
    if (end != null) {
      updatedAt = DateTime(
        _asInt(end['year'], fallback: 1970),
        _asInt(end['month'], fallback: 1),
        _asInt(end['day'], fallback: 1),
      );
    }

    return StygianOnslaughtStatus(
      isUnlocked: json['is_unlock'] as bool? ?? true,
      bestDifficultyId: _asInt(best?['difficulty']),
      bestTimeSeconds: _resolveStygianBestTimeSeconds(single),
      hasData: single['has_data'] as bool? ?? best != null,
      seasonName: schedule['name'] as String? ?? '',
      updatedAt: updatedAt,
    );
  }

  factory StygianOnslaughtStatus.fromCacheJson(Map<String, dynamic> json) =>
      StygianOnslaughtStatus(
        isUnlocked: json['is_unlock'] as bool? ?? true,
        bestDifficultyId: _asInt(json['best_difficulty_id']),
        bestTimeSeconds: _asInt(json['best_time_seconds']),
        hasData: json['has_data'] as bool? ?? false,
        seasonName: json['season_name'] as String? ?? '',
        updatedAt:
            json['updated_at'] == null
                ? null
                : DateTime.tryParse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    'is_unlock': isUnlocked,
    'best_difficulty_id': bestDifficultyId,
    'best_time_seconds': bestTimeSeconds,
    'has_data': hasData,
    'season_name': seasonName,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class AdventureStatus {
  const AdventureStatus({
    this.spiralAbyss,
    this.imaginariumTheater,
    this.stygianOnslaught,
    this.fetchedAt,
  });

  final SpiralAbyssStatus? spiralAbyss;
  final ImaginariumTheaterStatus? imaginariumTheater;
  final StygianOnslaughtStatus? stygianOnslaught;
  final DateTime? fetchedAt;

  DateTime? get latestUpdate {
    final dates =
        [
          spiralAbyss?.updatedAt,
          imaginariumTheater?.updatedAt,
          stygianOnslaught?.updatedAt,
          fetchedAt,
        ].whereType<DateTime>();
    if (dates.isEmpty) return fetchedAt;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  factory AdventureStatus.fromCacheJson(Map<String, dynamic> json) =>
      AdventureStatus(
        spiralAbyss:
            json['spiral_abyss'] == null
                ? null
                : SpiralAbyssStatus.fromJson(
                  json['spiral_abyss'] as Map<String, dynamic>,
                ),
        imaginariumTheater:
            json['imaginarium_theater'] == null
                ? null
                : ImaginariumTheaterStatus.fromCacheJson(
                  json['imaginarium_theater'] as Map<String, dynamic>,
                ),
        stygianOnslaught:
            json['stygian_onslaught'] == null
                ? null
                : StygianOnslaughtStatus.fromCacheJson(
                  json['stygian_onslaught'] as Map<String, dynamic>,
                ),
        fetchedAt:
            json['fetched_at'] == null
                ? null
                : DateTime.tryParse(json['fetched_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    if (spiralAbyss != null) 'spiral_abyss': spiralAbyss!.toJson(),
    if (imaginariumTheater != null)
      'imaginarium_theater': imaginariumTheater!.toJson(),
    if (stygianOnslaught != null)
      'stygian_onslaught': stygianOnslaught!.toJson(),
    if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String(),
  };
}

/// HoYoLAB は最高難易度の「3ボス合計クリア時間」を表示する。
/// `need_detail=true` 時は `challenge[].second` の合計が正確。
int _resolveStygianBestTimeSeconds(Map<String, dynamic> single) {
  final best = single['best'] as Map<String, dynamic>?;
  final challenges = single['challenge'] as List<dynamic>? ?? [];

  var challengeTotal = 0;
  for (final raw in challenges) {
    challengeTotal += _asInt((raw as Map<String, dynamic>)['second']);
  }

  final bestSecond = _asInt(best?['second']);
  if (challenges.isNotEmpty && challengeTotal > 0) {
    return challengeTotal;
  }
  return bestSecond;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
