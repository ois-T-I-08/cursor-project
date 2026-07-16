import '../gacha/calendar_event.dart';
import 'ley_line_overflow.dart';
import 'ley_line_overflow_catalog.dart';

/// カタログ・カレンダー・現在時刻から開催状態を解決する（純関数）。
LeyLineOverflowStatus resolveLeyLineOverflowStatus({
  required LeyLineOverflowCatalog catalog,
  required DateTime nowUtc,
  List<CalendarEvent> calendarEvents = const [],
  int? bonusUsedToday,
  bool catalogLoadFailed = false,
}) {
  if (catalogLoadFailed) {
    return const LeyLineOverflowStatus(
      isActive: false,
      resolveFailed: true,
    );
  }

  final now = nowUtc.toUtc();

  // 1) カレンダー API で名称マッチしたイベントを優先
  LeyLineOverflowEvent? fromCalendar;
  for (final cal in calendarEvents) {
    if (!catalog.defaults.matchesEventName(cal.name)) continue;
    if (!cal.hasSchedule) continue;
    fromCalendar = LeyLineOverflowEvent(
      eventId: cal.id.isEmpty ? 'calendar-${cal.name}' : cal.id,
      eventType: catalog.defaults.eventType,
      displayName: catalog.defaults.displayName,
      startAt: cal.start.toUtc(),
      endAt: cal.end.toUtc(),
      dailyBonusLimit: catalog.defaults.dailyBonusLimit,
      rewardMultiplier: catalog.defaults.rewardMultiplier,
      condensedResinEligible: false,
      eligibleLeyLineTypes: catalog.defaults.eligibleLeyLineTypes,
      enabled: true,
      source: 'calendarApi',
      updatedAt: now,
    );
    break;
  }

  // 2) ローカル/リモート設定のフォールバック（有効かつ期間内を優先、なければ直近）
  LeyLineOverflowEvent? fromConfig;
  for (final e in catalog.events) {
    if (!e.enabled) continue;
    if (e.isActiveAt(now)) {
      fromConfig = e;
      break;
    }
  }

  final resolved = fromCalendar ?? fromConfig;
  if (resolved == null) {
    return const LeyLineOverflowStatus(isActive: false);
  }

  final active = resolved.isActiveAt(now);
  return LeyLineOverflowStatus(
    isActive: active,
    event: resolved,
    bonusUsedToday: bonusUsedToday,
  );
}
