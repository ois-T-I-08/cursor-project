/// PU バナー種別
enum GachaBannerType {
  character,
  character2,
  weapon,
  chronicled,
}

/// 開催ステータス（表示・ソート用）
enum GachaBannerStatus {
  active,
  upcoming,
  ended,
}

/// ガチャ（PU）バナー1件
class GachaBanner {
  const GachaBanner({
    required this.id,
    required this.type,
    required this.name,
    required this.version,
    required this.start,
    required this.end,
    this.featured5Ids = const [],
    this.featured4Ids = const [],
    this.featuredWeaponIds = const [],
    this.sourceIcons = const {},
  });

  final String id;
  final GachaBannerType type;
  final String name;
  final String version;
  final DateTime start;
  final DateTime end;

  /// Amber / HoYo キャラ ID（5★ PU）
  final List<String> featured5Ids;

  /// Amber / HoYo キャラ ID（4★ PU）
  final List<String> featured4Ids;

  /// Amber / HoYo 武器 ID
  final List<String> featuredWeaponIds;

  /// Live API 由来のアイコン URL（ID → URL）。マスタ未同期時のフォールバック。
  final Map<String, String> sourceIcons;

  GachaBannerStatus statusAt(DateTime now) {
    if (now.isBefore(start)) return GachaBannerStatus.upcoming;
    if (now.isAfter(end)) return GachaBannerStatus.ended;
    return GachaBannerStatus.active;
  }

  GachaBanner copyWith({
    String? id,
    GachaBannerType? type,
    String? name,
    String? version,
    DateTime? start,
    DateTime? end,
    List<String>? featured5Ids,
    List<String>? featured4Ids,
    List<String>? featuredWeaponIds,
    Map<String, String>? sourceIcons,
  }) {
    return GachaBanner(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      version: version ?? this.version,
      start: start ?? this.start,
      end: end ?? this.end,
      featured5Ids: featured5Ids ?? this.featured5Ids,
      featured4Ids: featured4Ids ?? this.featured4Ids,
      featuredWeaponIds: featuredWeaponIds ?? this.featuredWeaponIds,
      sourceIcons: sourceIcons ?? this.sourceIcons,
    );
  }
}

int _statusRank(GachaBannerStatus s) => switch (s) {
      GachaBannerStatus.active => 0,
      GachaBannerStatus.upcoming => 1,
      GachaBannerStatus.ended => 2,
    };

/// 開催中 → 予告 → 終了済み。
/// 開催中は終了が近い順、他は開始の新しい順。
List<GachaBanner> sortGachaBanners(
  Iterable<GachaBanner> banners, {
  DateTime? now,
}) {
  final t = now ?? DateTime.now().toUtc();
  final list = banners.toList();
  list.sort((a, b) {
    final sa = a.statusAt(t);
    final sb = b.statusAt(t);
    final byStatus = _statusRank(sa).compareTo(_statusRank(sb));
    if (byStatus != 0) return byStatus;
    return switch (sa) {
      GachaBannerStatus.active => a.end.compareTo(b.end),
      GachaBannerStatus.upcoming ||
      GachaBannerStatus.ended =>
        b.start.compareTo(a.start),
    };
  });
  return list;
}

/// 履歴に live をマージ（同一 id、または type+開始+終了 が一致すれば live 優先）。
List<GachaBanner> mergeGachaBanners({
  required List<GachaBanner> history,
  required List<GachaBanner> live,
}) {
  String scheduleKey(GachaBanner b) =>
      '${b.type.name}|${b.start.toUtc().millisecondsSinceEpoch}|${b.end.toUtc().millisecondsSinceEpoch}';

  final byId = <String, GachaBanner>{
    for (final b in history) b.id: b,
  };
  final bySchedule = <String, String>{
    for (final b in history) scheduleKey(b): b.id,
  };

  for (final b in live) {
    final existingId = bySchedule[scheduleKey(b)];
    if (existingId != null && existingId != b.id) {
      byId.remove(existingId);
    }
    byId[b.id] = b;
    bySchedule[scheduleKey(b)] = b.id;
  }
  return byId.values.toList();
}

String gachaBannerTypeLabel(GachaBannerType type) => switch (type) {
      GachaBannerType.character => 'キャラクター祈願',
      GachaBannerType.character2 => 'キャラクター祈願2',
      GachaBannerType.weapon => '武器祈願',
      GachaBannerType.chronicled => '集録・追憶祈願',
    };
