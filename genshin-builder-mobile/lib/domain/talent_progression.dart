import 'level_config.dart';
import 'level_progression.dart';
import 'models/calculation_models.dart';

int snapTalentLevel(Object? value, [int max = talentLevelMax]) {
  final n = clampInt(value, 1, max);
  var closest = talentMarks.first;
  var minDiff = (n - closest).abs();
  for (final mark in talentMarks) {
    if (mark > max) break;
    final diff = (n - mark).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = mark;
    }
  }
  return closest;
}

TalentLevelUpgrade? getTalentUpgradeAtLevel(
  int level,
  List<TalentLevelUpgrade> upgrades,
) {
  for (final u in upgrades) {
    if (u.level == level) return u;
  }
  return null;
}

NextTalentRequirements? getNextTalentRequirements(
  int currentLevel,
  int max,
  List<TalentLevelUpgrade> upgrades,
) {
  final fromLevel = snapTalentLevel(currentLevel, max);
  if (fromLevel >= max) return null;

  final toLevel = fromLevel + 1;
  final upgrade = getTalentUpgradeAtLevel(toLevel, upgrades);
  final costItems = upgrade?.costItems ?? {};

  return NextTalentRequirements(
    fromLevel: fromLevel,
    toLevel: toLevel,
    materials:
        costItems.entries
            .map((e) => MaterialCost(materialId: e.key, count: e.value))
            .toList(),
    mora: upgrade?.coinCost ?? 0,
  );
}

List<({int level, List<MaterialCost> materials, int mora})>
getTalentUpgradeInfos(List<TalentLevelUpgrade> upgrades) {
  final filtered =
      upgrades.where((u) => u.level > 1 && u.costItems.isNotEmpty).toList()
        ..sort((a, b) => a.level.compareTo(b.level));
  return filtered
      .map(
        (u) => (
          level: u.level,
          materials:
              u.costItems.entries
                  .map((e) => MaterialCost(materialId: e.key, count: e.value))
                  .toList(),
          mora: u.coinCost,
        ),
      )
      .toList();
}
