import 'models/bookmark.dart';
import 'models/calculation_models.dart';
import 'level_progression.dart';
import 'talent_progression.dart';

List<RequirementLine> mergeRequirementLines(List<RequirementLine> lines) {
  final map = <String, RequirementLine>{};

  for (final line in lines) {
    final existing = map[line.materialId];
    if (existing != null) {
      map[line.materialId] = RequirementLine(
        materialId: existing.materialId,
        name: existing.name,
        count: existing.count + line.count,
        iconUrl: existing.iconUrl ?? line.iconUrl,
        isMora: existing.isMora || line.isMora,
      );
    } else {
      map[line.materialId] = line;
    }
  }

  final merged = map.values.toList()
    ..sort((a, b) {
      if (a.isMora) return 1;
      if (b.isMora) return -1;
      return a.name.compareTo(b.name);
    });
  return merged;
}

List<RequirementLine> getRangeLevelRequirements(
  int fromLevel,
  int toLevel,
  List<PromoteStage> promotes,
  String kind, {
  int weaponRarity = 5,
  UpgradeDataCache? cache,
  String Function(String materialId)? resolveName,
  String? Function(String materialId)? resolveIcon,
}) {
  final from = snapToLevelMark(fromLevel);
  final to = snapToLevelMark(toLevel);
  if (to <= from) return [];

  final materialMap = <String, int>{};
  final levelUpMap = <String, ({String name, int count})>{};
  var mora = 0;

  var current = from;
  while (current < to) {
    final stage = getNextStageRequirements(
      current,
      promotes,
      kind,
      weaponRarity,
      cache,
    );
    if (stage == null || stage.toLevel > to) break;

    for (final m in stage.materials) {
      materialMap[m.materialId] =
          (materialMap[m.materialId] ?? 0) + m.count;
    }
    for (final item in stage.levelUpMaterials) {
      final prev = levelUpMap[item.materialId];
      if (prev != null) {
        levelUpMap[item.materialId] = (
          name: prev.name,
          count: prev.count + item.count,
        );
      } else {
        levelUpMap[item.materialId] = (name: item.name, count: item.count);
      }
    }
    mora += stage.mora;
    current = stage.toLevel;
  }

  final lines = <RequirementLine>[];

  for (final entry in materialMap.entries) {
    lines.add(RequirementLine(
      materialId: entry.key,
      name: resolveName?.call(entry.key) ?? '素材 #${entry.key}',
      count: entry.value,
      iconUrl: resolveIcon?.call(entry.key),
    ));
  }
  for (final entry in levelUpMap.entries) {
    lines.add(RequirementLine(
      materialId: entry.key,
      name: resolveName?.call(entry.key) ?? entry.value.name,
      count: entry.value.count,
      iconUrl: resolveIcon?.call(entry.key),
    ));
  }
  if (mora > 0) {
    lines.add(RequirementLine(
      materialId: moraMaterialId,
      name: 'モラ',
      count: mora,
      isMora: true,
    ));
  }

  return mergeRequirementLines(lines);
}

List<RequirementLine> getRangeTalentRequirements(
  int fromLevel,
  int toLevel,
  int max,
  List<TalentLevelUpgrade> upgrades, {
  String Function(String materialId)? resolveName,
  String? Function(String materialId)? resolveIcon,
}) {
  final from = snapTalentLevel(fromLevel, max);
  final to = snapTalentLevel(toLevel, max);
  if (to <= from) return [];

  final materialMap = <String, int>{};
  var mora = 0;

  for (var level = from + 1; level <= to; level++) {
    final upgrade = getTalentUpgradeAtLevel(level, upgrades);
    if (upgrade == null) continue;
    for (final entry in upgrade.costItems.entries) {
      materialMap[entry.key] = (materialMap[entry.key] ?? 0) + entry.value;
    }
    mora += upgrade.coinCost;
  }

  final lines = <RequirementLine>[];
  for (final entry in materialMap.entries) {
    lines.add(RequirementLine(
      materialId: entry.key,
      name: resolveName?.call(entry.key) ?? '素材 #${entry.key}',
      count: entry.value,
      iconUrl: resolveIcon?.call(entry.key),
    ));
  }
  if (mora > 0) {
    lines.add(RequirementLine(
      materialId: moraMaterialId,
      name: 'モラ',
      count: mora,
      isMora: true,
    ));
  }

  return mergeRequirementLines(lines);
}

List<RequirementLine> nextStageToRequirementLines(
  List<MaterialCost> materials,
  List<LevelUpMaterialSuggestion> levelUpMaterials,
  int mora,
  String Function(String materialId) resolveName, {
  String? Function(String materialId)? resolveIcon,
}) {
  final lines = <RequirementLine>[];

  for (final m in materials) {
    lines.add(RequirementLine(
      materialId: m.materialId,
      name: resolveName(m.materialId),
      count: m.count,
      iconUrl: resolveIcon?.call(m.materialId),
    ));
  }
  for (final item in levelUpMaterials) {
    lines.add(RequirementLine(
      materialId: item.materialId,
      name: resolveName(item.materialId).isNotEmpty
          ? resolveName(item.materialId)
          : item.name,
      count: item.count,
      iconUrl: resolveIcon?.call(item.materialId),
    ));
  }
  if (mora > 0) {
    lines.add(RequirementLine(
      materialId: moraMaterialId,
      name: 'モラ',
      count: mora,
      isMora: true,
    ));
  }

  return lines;
}
