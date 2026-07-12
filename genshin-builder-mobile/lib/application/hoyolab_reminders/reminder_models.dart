/// P1-8B local reminder kinds (no secrets).
enum ReminderKind { resin, expedition }

enum ReminderDecisionType {
  scheduleAt,
  notifyImmediately,
  cancel,
  keepExisting,
  skipInvalid,
}

class ReminderDecision {
  const ReminderDecision._({
    required this.type,
    required this.kind,
    this.notifyAt,
    this.reasonCode,
    this.scheduleFingerprint,
  });

  factory ReminderDecision.scheduleAt({
    required ReminderKind kind,
    required DateTime notifyAt,
    required String scheduleFingerprint,
  }) =>
      ReminderDecision._(
        type: ReminderDecisionType.scheduleAt,
        kind: kind,
        notifyAt: notifyAt,
        scheduleFingerprint: scheduleFingerprint,
      );

  factory ReminderDecision.notifyImmediately({
    required ReminderKind kind,
    required String scheduleFingerprint,
  }) =>
      ReminderDecision._(
        type: ReminderDecisionType.notifyImmediately,
        kind: kind,
        scheduleFingerprint: scheduleFingerprint,
      );

  factory ReminderDecision.cancel(ReminderKind kind, {String? reasonCode}) =>
      ReminderDecision._(
        type: ReminderDecisionType.cancel,
        kind: kind,
        reasonCode: reasonCode,
      );

  factory ReminderDecision.keepExisting(ReminderKind kind) =>
      ReminderDecision._(
        type: ReminderDecisionType.keepExisting,
        kind: kind,
      );

  factory ReminderDecision.skipInvalid(
    ReminderKind kind,
    String reasonCode,
  ) =>
      ReminderDecision._(
        type: ReminderDecisionType.skipInvalid,
        kind: kind,
        reasonCode: reasonCode,
      );

  final ReminderDecisionType type;
  final ReminderKind kind;
  final DateTime? notifyAt;
  final String? reasonCode;
  final String? scheduleFingerprint;
}

class ReminderPriorState {
  const ReminderPriorState({
    required this.resinWasAtOrAbove190,
    required this.expeditionAllComplete,
    this.resinScheduledAt,
    this.resinScheduleFingerprint,
    this.expeditionScheduledAt,
    this.expeditionScheduleFingerprint,
  });

  final bool resinWasAtOrAbove190;
  final bool expeditionAllComplete;
  final DateTime? resinScheduledAt;
  final String? resinScheduleFingerprint;
  final DateTime? expeditionScheduledAt;
  final String? expeditionScheduleFingerprint;
}

class ExpeditionReminderInput {
  const ExpeditionReminderInput({
    required this.status,
    required this.hasRemainingTimeFromApi,
    required this.remainingSeconds,
  });

  final String status;
  final bool hasRemainingTimeFromApi;
  final int? remainingSeconds;
}

class ReminderSnapshotInput {
  const ReminderSnapshotInput({
    required this.fetchedAt,
    required this.accountGeneration,
    required this.currentResin,
    required this.maxResin,
    required this.hasMaxResinFromApi,
    required this.resinRecoveryTimeRaw,
    required this.expeditions,
  });

  final DateTime fetchedAt;
  final String accountGeneration;
  final int currentResin;
  final int maxResin;
  final bool hasMaxResinFromApi;
  final String resinRecoveryTimeRaw;
  final List<ExpeditionReminderInput> expeditions;
}

/// Fixed notification ids / channels / payloads (no secrets).
abstract final class ReminderNotificationIds {
  static const resin = 1001;
  static const expedition = 1002;

  static const resinChannelId = 'resin_reminders';
  static const expeditionChannelId = 'expedition_reminders';

  static const resinPayload = 'section=resin';
  static const expeditionPayload = 'section=expedition';

  static const resinTitle = '天然樹脂が190以上になっています';
  static const resinBody = '天然樹脂が上限に近づいています。';
  static const expeditionTitle = '探索派遣がすべて完了しました';
  static const expeditionBody = '5件の探索派遣が完了しています。';

  /// Safety ceiling for derived wait (not a resin interval guess).
  static const maxScheduleHorizon = Duration(days: 14);
}
