/// 地脈の奔流（Ley Line Overflow）イベント定義とボーナス周回計算。
library;

/// テスト可能な現在時刻供給（UTC を返すこと）。
typedef Clock = DateTime Function();

/// ボーナス対象の地脈種別。
enum LeyLineOverflowLeyLineType {
  exp,
  mora,
}

/// 設定 / API から得た開催情報。
class LeyLineOverflowEvent {
  const LeyLineOverflowEvent({
    required this.eventId,
    required this.eventType,
    required this.displayName,
    required this.startAt,
    required this.endAt,
    required this.dailyBonusLimit,
    required this.eligibleLeyLineTypes,
    required this.source,
    this.rewardMultiplier = 2,
    this.condensedResinEligible = false,
    this.enabled = true,
    this.updatedAt,
  });

  final String eventId;
  final String eventType;
  final String displayName;

  /// UTC。
  final DateTime startAt;

  /// UTC（終了時刻ちょうどは期間内。CalendarEvent と同一）。
  final DateTime endAt;

  final int dailyBonusLimit;
  final List<LeyLineOverflowLeyLineType> eligibleLeyLineTypes;

  /// 1ボーナス周回あたりの通常報酬換算倍率（通常は 2）。
  final int rewardMultiplier;

  /// 地脈の奔流ボーナスは通常樹脂のみ。濃縮樹脂は対象外。
  final bool condensedResinEligible;

  final bool enabled;
  final String source;
  final DateTime? updatedAt;

  bool isEligible(LeyLineOverflowLeyLineType type) =>
      eligibleLeyLineTypes.contains(type);

  /// `[startAt, endAt]` — 開始・終了ちょうどは期間内（CalendarEvent と同一）。
  bool isActiveAt(DateTime nowUtc) {
    if (!enabled) return false;
    if (dailyBonusLimit <= 0 || rewardMultiplier < 2) return false;
    if (endAt.toUtc().isBefore(startAt.toUtc())) return false;
    final now = nowUtc.toUtc();
    final start = startAt.toUtc();
    final end = endAt.toUtc();
    return !now.isBefore(start) && !now.isAfter(end);
  }
}

/// 開催解決結果（取得失敗時は [inactive]）。
class LeyLineOverflowStatus {
  const LeyLineOverflowStatus({
    required this.isActive,
    this.event,
    this.bonusUsedToday,
    this.resolveFailed = false,
  });

  static const inactive = LeyLineOverflowStatus(isActive: false);

  final bool isActive;
  final LeyLineOverflowEvent? event;

  /// null = 使用済み不明 → 最大適用時の目安。
  final int? bonusUsedToday;

  /// 設定・API 取得に失敗し、開催中と断定できない。
  final bool resolveFailed;

  /// 本日の残りボーナス回数が観測値として分かっているか。
  bool get remainingCountKnown => isActive && bonusUsedToday != null;

  int? get remainingBonusToday {
    final e = event;
    if (e == null || !isActive) return null;
    final used = bonusUsedToday;
    if (used == null) return e.dailyBonusLimit;
    final rem = e.dailyBonusLimit - used;
    return rem < 0 ? 0 : rem;
  }

  bool get isMaxEstimate => isActive && !remainingCountKnown;
}

/// 地脈1種分のボーナス内訳。
class LeyLineOverflowBreakdown {
  const LeyLineOverflowBreakdown({
    required this.normalEquivalentRuns,
    required this.bonusRunsApplied,
    required this.normalRunsAfterBonus,
    required this.actualRuns,
    required this.resinTotal,
    required this.dailyBonusLimit,
    required this.remainingBonusCapacity,
    required this.isMaxEstimate,
    required this.eventDisplayName,
    required this.rewardMultiplier,
    this.bonusUsedToday,
  });

  /// イベントなしの場合の必要周回数（通常報酬換算）。
  final int normalEquivalentRuns;

  /// ボーナス適用回数。
  final int bonusRunsApplied;

  /// ボーナス後に必要な通常周回。
  final int normalRunsAfterBonus;

  /// 実際に回す回数（樹脂消費回数）。
  final int actualRuns;

  final int resinTotal;
  final int dailyBonusLimit;
  final int remainingBonusCapacity;
  final bool isMaxEstimate;
  final String eventDisplayName;
  final int rewardMultiplier;
  final int? bonusUsedToday;
}

/// 通常周回数へボーナスを適用する。
///
/// [normalEquivalentRuns] は所持差し引き後の不足から算出した通常地脈回数。
/// 濃縮樹脂はここでは扱わない（樹脂/回は通常地脈の resinPerRun）。
LeyLineOverflowBreakdown? applyLeyLineOverflowBonus({
  required int normalEquivalentRuns,
  required int resinPerRun,
  required LeyLineOverflowStatus status,
  required LeyLineOverflowLeyLineType leyLineType,
  required DateTime nowUtc,
}) {
  if (normalEquivalentRuns <= 0 || resinPerRun < 0) return null;
  final event = status.event;
  if (!status.isActive || event == null || status.resolveFailed) return null;
  if (!event.isActiveAt(nowUtc)) return null;
  if (!event.isEligible(leyLineType)) return null;

  final multiplier = event.rewardMultiplier < 2 ? 2 : event.rewardMultiplier;
  final remaining = status.remainingBonusToday ?? 0;
  if (remaining <= 0) {
    return LeyLineOverflowBreakdown(
      normalEquivalentRuns: normalEquivalentRuns,
      bonusRunsApplied: 0,
      normalRunsAfterBonus: normalEquivalentRuns,
      actualRuns: normalEquivalentRuns,
      resinTotal: normalEquivalentRuns * resinPerRun,
      dailyBonusLimit: event.dailyBonusLimit,
      remainingBonusCapacity: 0,
      isMaxEstimate: status.isMaxEstimate,
      eventDisplayName: event.displayName,
      rewardMultiplier: multiplier,
      bonusUsedToday: status.bonusUsedToday,
    );
  }

  // ボーナス1回 = 通常報酬 × multiplier 分。
  // usefulBonus ≤ ceil(normal / multiplier) かつ remaining で上限。
  // （単純に normal - remaining とはしない）
  final maxUsefulBonus =
      (normalEquivalentRuns + multiplier - 1) ~/ multiplier;
  final bonusRuns =
      remaining < maxUsefulBonus ? remaining : maxUsefulBonus;
  final coveredByBonus = bonusRuns * multiplier;
  final remainingNormal = normalEquivalentRuns - coveredByBonus;
  final normalRuns = remainingNormal < 0 ? 0 : remainingNormal;
  // 通常樹脂の周回数のみ（濃縮樹脂はボーナス対象外・別換算）。
  final actualRuns = bonusRuns + normalRuns;

  return LeyLineOverflowBreakdown(
    normalEquivalentRuns: normalEquivalentRuns,
    bonusRunsApplied: bonusRuns,
    normalRunsAfterBonus: normalRuns,
    actualRuns: actualRuns,
    resinTotal: actualRuns * resinPerRun,
    dailyBonusLimit: event.dailyBonusLimit,
    remainingBonusCapacity: remaining,
    isMaxEstimate: status.isMaxEstimate,
    eventDisplayName: event.displayName,
    rewardMultiplier: multiplier,
    bonusUsedToday: status.bonusUsedToday,
  );
}

LeyLineOverflowLeyLineType? leyLineTypeFromFarmKindName(String key) {
  return switch (key) {
    'exp' || 'leyLineExp' => LeyLineOverflowLeyLineType.exp,
    'mora' || 'leyLineMora' => LeyLineOverflowLeyLineType.mora,
    _ => null,
  };
}

List<LeyLineOverflowLeyLineType> parseEligibleLeyLineTypes(Object? raw) {
  if (raw is! List) {
    return const [
      LeyLineOverflowLeyLineType.exp,
      LeyLineOverflowLeyLineType.mora,
    ];
  }
  final out = <LeyLineOverflowLeyLineType>[];
  for (final e in raw) {
    final t = leyLineTypeFromFarmKindName('$e');
    if (t != null && !out.contains(t)) out.add(t);
  }
  return out.isEmpty
      ? const [
          LeyLineOverflowLeyLineType.exp,
          LeyLineOverflowLeyLineType.mora,
        ]
      : out;
}
