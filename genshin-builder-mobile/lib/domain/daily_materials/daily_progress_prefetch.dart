import '../models/calculation_models.dart';
import 'daily_material_models.dart';
import 'daily_material_planner.dart';

/// 指定曜日の天賦素材を使うキャラ ID を抽出する純関数
Set<String> characterIdsNeedingTalentMaterialsOnDay({
  required DailyMaterialSchedule schedule,
  required int weekday,
  required Map<String, Map<String, List<TalentLevelUpgrade>>> talentsByCharacterId,
}) {
  final todayIds = <String>{};
  for (final series in schedule.seriesForDay(
    weekday,
    kind: DailyMaterialKind.talentBook,
  )) {
    todayIds.addAll(series.materialIds);
  }
  if (todayIds.isEmpty) return {};

  final result = <String>{};
  for (final entry in talentsByCharacterId.entries) {
    final used = materialIdsFromTalents(entry.value);
    if (used.any(todayIds.contains)) {
      result.add(entry.key);
    }
  }
  return result;
}
