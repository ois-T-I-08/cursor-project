class HoyolabExpedition {
  const HoyolabExpedition({
    required this.status,
    required this.remainingTime,
  });

  final String status;
  final String remainingTime;

  bool get isFinished => status.toLowerCase() == 'finished';

  factory HoyolabExpedition.fromJson(Map<String, dynamic> json) =>
      HoyolabExpedition(
        status: json['status'] as String? ?? '',
        remainingTime: json['remaining_time'] as String? ?? '0',
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'remaining_time': remainingTime,
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
  });

  final int currentResin;
  final int maxResin;
  final String resinRecoveryTime;
  final int finishedTaskNum;
  final int totalTaskNum;
  final int currentHomeCoin;
  final int maxHomeCoin;
  final List<HoyolabExpedition> expeditions;

  int get remainingResin => maxResin - currentResin;

  bool get dailyTasksComplete => finishedTaskNum >= totalTaskNum;

  int get activeExpeditions =>
      expeditions.where((e) => !e.isFinished).length;

  int get finishedExpeditions =>
      expeditions.where((e) => e.isFinished).length;

  factory DailyNote.fromJson(Map<String, dynamic> json) {
    final expeditionsRaw = json['expeditions'] as List<dynamic>? ?? [];
    return DailyNote(
      currentResin: DailyNote.asInt(json['current_resin']),
      maxResin: DailyNote.asInt(json['max_resin'], fallback: 160),
      resinRecoveryTime: json['resin_recovery_time'] as String? ?? '0',
      finishedTaskNum: DailyNote.asInt(json['finished_task_num']),
      totalTaskNum: DailyNote.asInt(json['total_task_num'], fallback: 4),
      currentHomeCoin: DailyNote.asInt(json['current_home_coin']),
      maxHomeCoin: DailyNote.asInt(json['max_home_coin'], fallback: 2400),
      expeditions: expeditionsRaw
          .map((e) => HoyolabExpedition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'current_resin': currentResin,
        'max_resin': maxResin,
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
