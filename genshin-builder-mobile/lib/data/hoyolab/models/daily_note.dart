class HoyolabExpedition {
  const HoyolabExpedition({
    required this.status,
    required this.remainingTime,
    this.hasRemainingTimeFromApi = false,
  });

  final String status;
  final String remainingTime;

  /// `remaining_time` が API 由来で非負整数として確定している場合のみ true。
  final bool hasRemainingTimeFromApi;

  bool get isFinished => status.toLowerCase() == 'finished';

  bool get isOngoing => status.toLowerCase() == 'ongoing';

  /// API 由来で有効な残り秒。欠落・不正時は null。
  int? get remainingSecondsFromApi {
    if (!hasRemainingTimeFromApi) return null;
    return DailyNote.tryParseNonNegativeInt(remainingTime);
  }

  factory HoyolabExpedition.fromJson(Map<String, dynamic> json) =>
      HoyolabExpedition.fromJsonSource(json, fromApi: true);

  /// [fromApi]: true なら presence フラグ欠落時にキー有無から推定。
  /// false（disk cache）ならフラグ欠落は false（旧 cache は予約しない）。
  factory HoyolabExpedition.fromJsonSource(
    Map<String, dynamic> json, {
    required bool fromApi,
  }) {
    final raw = json['remaining_time'];
    final parsed = DailyNote.tryParseNonNegativeInt(raw);
    final inferred = json.containsKey('remaining_time') && parsed != null;

    final bool hasFromApi;
    if (json.containsKey('has_remaining_time_from_api')) {
      hasFromApi = json['has_remaining_time_from_api'] == true;
    } else if (fromApi) {
      hasFromApi = inferred;
    } else {
      hasFromApi = false;
    }

    return HoyolabExpedition(
      status: json['status'] as String? ?? '',
      remainingTime: raw?.toString() ?? '0',
      hasRemainingTimeFromApi: hasFromApi,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'remaining_time': remainingTime,
        'has_remaining_time_from_api': hasRemainingTimeFromApi,
      };
}

class DailyNote {
  const DailyNote({
    required this.currentResin,
    required this.maxResin,
    required this.resinRecoveryTime,
    required this.finishedTaskNum,
    required this.totalTaskNum,
    required this.currentHomeCoin,
    required this.maxHomeCoin,
    required this.expeditions,
    this.hasMaxResinFromApi = false,
  });

  final int currentResin;
  final int maxResin;
  final String resinRecoveryTime;
  final int finishedTaskNum;
  final int totalTaskNum;
  final int currentHomeCoin;
  final int maxHomeCoin;
  final List<HoyolabExpedition> expeditions;

  /// `max_resin` が API 由来で有効整数として確定している場合のみ true。
  final bool hasMaxResinFromApi;

  int get remainingResin => maxResin - currentResin;

  bool get dailyTasksComplete => finishedTaskNum >= totalTaskNum;

  int get activeExpeditions =>
      expeditions.where((e) => !e.isFinished).length;

  int get finishedExpeditions =>
      expeditions.where((e) => e.isFinished).length;

  factory DailyNote.fromJson(Map<String, dynamic> json) =>
      DailyNote.fromJsonSource(json, fromApi: true);

  factory DailyNote.fromJsonSource(
    Map<String, dynamic> json, {
    required bool fromApi,
  }) {
    final expeditionsRaw = json['expeditions'] as List<dynamic>? ?? [];
    final maxRaw = json['max_resin'];
    final maxParsed = tryParseInt(maxRaw);

    final bool hasMax;
    if (json.containsKey('has_max_resin_from_api')) {
      hasMax = json['has_max_resin_from_api'] == true;
    } else if (fromApi) {
      hasMax = json.containsKey('max_resin') && maxParsed != null;
    } else {
      hasMax = false;
    }

    return DailyNote(
      currentResin: DailyNote.asInt(json['current_resin']),
      maxResin: maxParsed ?? 160,
      hasMaxResinFromApi: hasMax,
      resinRecoveryTime: json['resin_recovery_time'] as String? ?? '0',
      finishedTaskNum: DailyNote.asInt(json['finished_task_num']),
      totalTaskNum: DailyNote.asInt(json['total_task_num'], fallback: 4),
      currentHomeCoin: DailyNote.asInt(json['current_home_coin']),
      maxHomeCoin: DailyNote.asInt(json['max_home_coin'], fallback: 2400),
      expeditions: expeditionsRaw
          .map(
            (e) => HoyolabExpedition.fromJsonSource(
              e as Map<String, dynamic>,
              fromApi: fromApi,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'current_resin': currentResin,
        'max_resin': maxResin,
        'has_max_resin_from_api': hasMaxResinFromApi,
        'resin_recovery_time': resinRecoveryTime,
        'finished_task_num': finishedTaskNum,
        'total_task_num': totalTaskNum,
        'current_home_coin': currentHomeCoin,
        'max_home_coin': maxHomeCoin,
        'expeditions':
            expeditions.map((e) => e.toJson()).toList(growable: false),
      };

  static int asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? tryParseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int? tryParseNonNegativeInt(dynamic value) {
    final parsed = tryParseInt(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
}

class HoyolabGameRole {
  const HoyolabGameRole({
    required this.uid,
    required this.nickname,
    required this.level,
    required this.region,
  });

  final String uid;
  final String nickname;
  final int level;
  final String region;

  factory HoyolabGameRole.fromJson(
    Map<String, dynamic> json, {
    required String region,
  }) =>
      HoyolabGameRole(
        uid: '${json['game_uid'] ?? json['uid'] ?? ''}',
        nickname: json['nickname'] as String? ?? '旅行者',
        level: DailyNote.asInt(json['level']),
        region: region,
      );
}

class HoyolabRegion {
  const HoyolabRegion({required this.region, required this.name});

  final String region;
  final String name;

  factory HoyolabRegion.fromJson(Map<String, dynamic> json) => HoyolabRegion(
        region: json['region'] as String? ?? '',
        name: json['name'] as String? ?? json['region'] as String? ?? '',
      );
}

class HoyolabUserInfo {
  const HoyolabUserInfo({required this.accountName});

  final String accountName;

  factory HoyolabUserInfo.fromJson(Map<String, dynamic> json) =>
      HoyolabUserInfo(
        accountName: json['account_name'] as String? ?? 'HoYoLAB',
      );
}

class HoyolabSession {
  const HoyolabSession({
    required this.isLinked,
    this.uid,
    this.region,
    this.nickname,
    this.accountName,
  });

  final bool isLinked;
  final String? uid;
  final String? region;
  final String? nickname;
  final String? accountName;

  bool get canFetchDailyNote =>
      isLinked && uid != null && uid!.isNotEmpty && region != null;

  HoyolabSession copyWith({
    bool? isLinked,
    String? uid,
    String? region,
    String? nickname,
    String? accountName,
  }) =>
      HoyolabSession(
        isLinked: isLinked ?? this.isLinked,
        uid: uid ?? this.uid,
        region: region ?? this.region,
        nickname: nickname ?? this.nickname,
        accountName: accountName ?? this.accountName,
      );

  static const unlinked = HoyolabSession(isLinked: false);
}
