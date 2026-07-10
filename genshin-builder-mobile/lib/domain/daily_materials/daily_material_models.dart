import '../models/master_models.dart';

/// 素材シリーズ種別（将来: 聖遺物秘境・週ボス等を追加）
enum DailyMaterialKind {
  talentBook,
  weaponAscension,
}

/// 残り必要数の表示状態
enum DailyRemainingStatus {
  /// 育成データなし（計算不能）
  unknown,

  /// 不足なし
  complete,

  /// 不足あり（[DailyMaterialConsumer.remainingCount] > 0）
  needed,
}

/// 1 シリーズ（例: 天光 / 高塔の王）
class DailyMaterialSeries {
  const DailyMaterialSeries({
    required this.id,
    required this.name,
    required this.region,
    required this.kind,
    required this.days,
    required this.materialIds,
  });

  final String id;
  final String name;
  final String region;
  final DailyMaterialKind kind;

  /// ISO 曜日（1=月 … 7=日）。日曜はスケジュール側で全開放扱い。
  final List<int> days;
  final List<String> materialIds;

  Set<String> get materialIdSet => materialIds.toSet();

  /// 表示用アイコン（最高レアの素材 ID）
  String get displayMaterialId =>
      materialIds.isEmpty ? '' : materialIds.last;

  bool isAvailableOn(int isoWeekday) {
    if (isoWeekday == DateTime.sunday) return true;
    return days.contains(isoWeekday);
  }

  factory DailyMaterialSeries.fromJson(
    Map<String, dynamic> json,
    DailyMaterialKind kind,
  ) {
    final days = (json['days'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).toInt())
        .toList(growable: false);
    final materialIds = (json['materialIds'] as List<dynamic>? ?? const [])
        .map((e) => '$e')
        .toList(growable: false);
    return DailyMaterialSeries(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      region: json['region'] as String? ?? '',
      kind: kind,
      days: days,
      materialIds: materialIds,
    );
  }
}

/// スケジュール全体（JSON 正本）
class DailyMaterialSchedule {
  const DailyMaterialSchedule({
    required this.version,
    required this.talentSeries,
    required this.weaponSeries,
  });

  final int version;
  final List<DailyMaterialSeries> talentSeries;
  final List<DailyMaterialSeries> weaponSeries;

  Iterable<DailyMaterialSeries> get allSeries sync* {
    yield* talentSeries;
    yield* weaponSeries;
  }

  List<DailyMaterialSeries> seriesForDay(
    int isoWeekday, {
    DailyMaterialKind? kind,
  }) {
    return allSeries
        .where((s) => kind == null || s.kind == kind)
        .where((s) => s.isAvailableOn(isoWeekday))
        .toList(growable: false);
  }

  /// materialId → series（逆引き）
  Map<String, DailyMaterialSeries> buildMaterialIndex() {
    final map = <String, DailyMaterialSeries>{};
    for (final series in allSeries) {
      for (final id in series.materialIds) {
        map[id] = series;
      }
    }
    return map;
  }

  factory DailyMaterialSchedule.fromJson(Map<String, dynamic> json) {
    final talent = (json['talentSeries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => DailyMaterialSeries.fromJson(e, DailyMaterialKind.talentBook))
        .toList(growable: false);
    final weapon = (json['weaponSeries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (e) =>
              DailyMaterialSeries.fromJson(e, DailyMaterialKind.weaponAscension),
        )
        .toList(growable: false);
    return DailyMaterialSchedule(
      version: (json['version'] as num?)?.toInt() ?? 1,
      talentSeries: talent,
      weaponSeries: weapon,
    );
  }
}

/// 原神の日替わりリセット（JST 4:00）を考慮した「ゲーム内の今日」
DateTime genshinGameDate([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  final jst = utc.add(const Duration(hours: 9));
  if (jst.hour < 4) {
    return DateTime(jst.year, jst.month, jst.day)
        .subtract(const Duration(days: 1));
  }
  return DateTime(jst.year, jst.month, jst.day);
}

int genshinIsoWeekday([DateTime? now]) => genshinGameDate(now).weekday;

const weekdayLabelsJa = <int, String>{
  DateTime.monday: '月',
  DateTime.tuesday: '火',
  DateTime.wednesday: '水',
  DateTime.thursday: '木',
  DateTime.friday: '金',
  DateTime.saturday: '土',
  DateTime.sunday: '日',
};

/// 装備キャラ（武器カード用）
class DailyEquippedCharacter {
  const DailyEquippedCharacter({
    required this.id,
    required this.name,
    this.iconUrl,
  });

  final String id;
  final String name;
  final String? iconUrl;
}

/// シリーズに紐づく育成対象（キャラ or 武器）
class DailyMaterialConsumer {
  const DailyMaterialConsumer({
    required this.id,
    required this.name,
    this.iconUrl,
    this.remainingStatus = DailyRemainingStatus.unknown,
    this.remainingCount = 0,
    this.remainingByMaterialId = const {},
    this.nextStageByMaterialId = const {},
    this.isOwned = false,
    this.isBuilding = false,
    this.weaponType,
    this.rarity,
    this.weaponLevel,
    this.weaponRefinement,
    this.equippedCharacters = const [],
  });

  final String id;
  final String name;
  final String? iconUrl;
  final DailyRemainingStatus remainingStatus;

  /// シリーズ内素材の合計不足（ソート用）
  final int remainingCount;

  /// materialId → 最大までの不足数
  final Map<String, int> remainingByMaterialId;

  /// materialId → 次の段階までの不足数
  final Map<String, int> nextStageByMaterialId;
  final bool isOwned;
  final bool isBuilding;

  /// 武器の場合のみ
  final String? weaponType;
  final int? rarity;
  final int? weaponLevel;
  final int? weaponRefinement;
  final List<DailyEquippedCharacter> equippedCharacters;

  bool get isEquipped => equippedCharacters.isNotEmpty;
  bool get hasShortage =>
      remainingStatus == DailyRemainingStatus.needed && remainingCount > 0;
  bool get isComplete => remainingStatus == DailyRemainingStatus.complete;
}

/// 武器種などのグループ見出し付きリスト
class DailyMaterialConsumerGroup {
  const DailyMaterialConsumerGroup({
    required this.key,
    required this.label,
    required this.consumers,
  });

  final String key;
  final String label;
  final List<DailyMaterialConsumer> consumers;
}

/// UI 用の 1 シリーズカード
class DailyMaterialSeriesCardData {
  const DailyMaterialSeriesCardData({
    required this.series,
    required this.materials,
    required this.consumerGroups,
    required this.remainingByMaterialId,
    required this.nextStageByMaterialId,
  });

  final DailyMaterialSeries series;
  final List<MasterMaterial> materials;
  final List<DailyMaterialConsumerGroup> consumerGroups;

  /// シリーズ内各素材の最大までの不足合計
  final Map<String, int> remainingByMaterialId;

  /// シリーズ内各素材の次の段階までの不足合計
  final Map<String, int> nextStageByMaterialId;

  int get totalRemaining =>
      remainingByMaterialId.values.fold(0, (s, n) => s + n);

  List<DailyMaterialConsumer> get consumers => [
        for (final g in consumerGroups) ...g.consumers,
      ];

  MasterMaterial? get displayMaterial =>
      materials.isEmpty ? null : materials.last;

  int remainingFor(String materialId) =>
      remainingByMaterialId[materialId] ?? 0;

  int nextStageFor(String materialId) =>
      nextStageByMaterialId[materialId] ?? 0;
}

/// 曜日画面の集計結果
class DailyMaterialsPlan {
  const DailyMaterialsPlan({
    required this.weekday,
    required this.talentCards,
    required this.weaponCards,
  });

  final int weekday;
  final List<DailyMaterialSeriesCardData> talentCards;
  final List<DailyMaterialSeriesCardData> weaponCards;

  bool get isEmpty => talentCards.isEmpty && weaponCards.isEmpty;
}
