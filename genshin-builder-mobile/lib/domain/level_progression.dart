import 'level_config.dart';
import 'models/calculation_models.dart';
import 'weapon_exp.dart';

int clampInt(Object? value, int min, int max) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || parsed.isNaN) return min;
  return parsed.round().clamp(min, max);
}

int snapToLevelMark(Object? value) =>
    snapToMarks(value, levelMarksList, levelMax);

int snapToMarks(Object? value, List<int> marks, int max) {
  final min = marks.first;
  final n = clampInt(value, min, max);
  var closest = min;
  var minDiff = (n - closest).abs();
  for (final mark in marks) {
    if (mark > max) continue;
    final diff = (n - mark).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = mark;
    }
  }
  return closest;
}

double levelToVisualRatio(int level, int displayMax) =>
    clampInt(level, 1, displayMax) / displayMax;

int? getNextMilestone(int level) {
  final snapped = snapToLevelMark(level);
  final idx = levelMarksList.indexOf(snapped);
  if (idx < 0 || idx >= levelMarksList.length - 1) return null;
  return levelMarksList[idx + 1];
}

int getRequiredPromoteLevel(int level, List<PromoteStage> promotes) {
  if (level <= 1) return 0;
  final sorted = [...promotes]
    ..sort((a, b) => a.unlockMaxLevel.compareTo(b.unlockMaxLevel));
  for (final p in sorted) {
    if (p.unlockMaxLevel >= level) return p.promoteLevel;
  }
  return sorted.isEmpty ? 0 : sorted.last.promoteLevel;
}

void _mergeMaterials(Map<String, int> target, Map<String, int> items) {
  for (final entry in items.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

int _resolveRarity(int rarity) {
  if (rarity >= 5) return 5;
  if (rarity == 4) return 4;
  return 3;
}

int getExpBetweenMarks(
  int from,
  int to,
  String kind,
  int weaponRarity, [
  UpgradeDataCache? cache,
]) {
  final fromMark = snapToLevelMark(from);
  final toMark = snapToLevelMark(to);
  if (toMark <= fromMark) return 0;

  if (cache != null && cache.levelExpSegments.isNotEmpty) {
    final rarity = kind == 'character' ? 0 : _resolveRarity(weaponRarity);
    var total = 0;
    final startIdx = levelMarksList.indexOf(fromMark);
    for (var i = startIdx; i < levelMarksList.length - 1; i++) {
      final a = levelMarksList[i];
      final b = levelMarksList[i + 1];
      if (b <= fromMark) continue;
      if (a >= toMark) break;
      LevelExpSegment? seg;
      for (final s in cache.levelExpSegments) {
        if (s.targetType == kind &&
            s.rarity == rarity &&
            s.fromLevel == a &&
            s.toLevel == b) {
          seg = s;
          break;
        }
      }
      total += seg?.expRequired ?? 0;
      if (b >= toMark) break;
    }
    if (total > 0) return total;
  }

  if (kind == 'weapon') {
    return getWeaponExpBetweenMarks(fromMark, toMark, weaponRarity);
  }

  var total = 0;
  final startIdx = levelMarksList.indexOf(fromMark);
  for (var i = startIdx; i < levelMarksList.length - 1; i++) {
    final a = levelMarksList[i];
    final b = levelMarksList[i + 1];
    if (b <= fromMark) continue;
    if (a >= toMark) break;
    total += characterExpBetweenMarks['$a-$b'] ?? 0;
    if (b >= toMark) break;
  }
  return total;
}

List<({String materialId, String name, int exp})> _getLevelUpItems(
  String kind, [
  UpgradeDataCache? cache,
]) {
  final fromCache =
      (cache?.levelUpMaterials ?? [])
          .where((m) => m.targetType == kind)
          .map((m) => (materialId: m.materialId, name: m.name, exp: m.exp))
          .toList()
        ..sort((a, b) => b.exp.compareTo(a.exp));

  if (fromCache.isNotEmpty) return fromCache;

  if (kind == 'weapon') {
    return weaponEnhancementOres
        .map((o) => (materialId: o.id, name: o.name, exp: o.exp))
        .toList();
  }

  return expBooks
      .map((b) => (materialId: b.id, name: b.name, exp: b.exp))
      .toList();
}

List<LevelUpMaterialSuggestion> suggestLevelUpMaterials(
  int totalExp,
  String kind, [
  UpgradeDataCache? cache,
]) {
  if (totalExp <= 0) return [];

  final items = _getLevelUpItems(kind, cache);
  var remaining = totalExp;
  final result = <LevelUpMaterialSuggestion>[];

  for (final item in items) {
    final count = remaining ~/ item.exp;
    if (count > 0) {
      result.add(
        LevelUpMaterialSuggestion(
          materialId: item.materialId,
          name: item.name,
          count: count,
        ),
      );
      remaining -= count * item.exp;
    }
  }

  if (remaining > 0 && items.isNotEmpty) {
    final smallest = items.last;
    final extra = (remaining / smallest.exp).ceil();
    final existing =
        result.where((r) => r.materialId == smallest.materialId).firstOrNull;
    if (existing != null) {
      final idx = result.indexOf(existing);
      result[idx] = LevelUpMaterialSuggestion(
        materialId: existing.materialId,
        name: existing.name,
        count: existing.count + extra,
      );
    } else {
      result.add(
        LevelUpMaterialSuggestion(
          materialId: smallest.materialId,
          name: smallest.name,
          count: extra,
        ),
      );
    }
  }

  return result;
}

NextStageRequirements? getNextStageRequirements(
  int currentLevel,
  List<PromoteStage> promotes,
  String kind,
  int weaponRarity, [
  UpgradeDataCache? cache,
]) {
  final fromLevel = snapToLevelMark(currentLevel);
  final toLevel = getNextMilestone(fromLevel);
  if (toLevel == null) return null;

  final currentPromote = getRequiredPromoteLevel(fromLevel, promotes);
  final targetPromote = getRequiredPromoteLevel(toLevel, promotes);
  final needsAscension = targetPromote > currentPromote;

  final materialMap = <String, int>{};
  var mora = 0;

  if (needsAscension) {
    for (var pl = currentPromote + 1; pl <= targetPromote; pl++) {
      PromoteStage? stage;
      for (final p in promotes) {
        if (p.promoteLevel == pl) {
          stage = p;
          break;
        }
      }
      if (stage == null) continue;
      _mergeMaterials(materialMap, stage.costItems);
      mora += stage.coinCost;
    }
  }

  final expTotal = getExpBetweenMarks(
    fromLevel,
    toLevel,
    kind,
    weaponRarity,
    cache,
  );
  final levelUpMora = (expTotal / 10).round();
  final levelUpMaterials = suggestLevelUpMaterials(expTotal, kind, cache);

  return NextStageRequirements(
    fromLevel: fromLevel,
    toLevel: toLevel,
    needsAscension: needsAscension,
    materials:
        materialMap.entries
            .map((e) => MaterialCost(materialId: e.key, count: e.value))
            .toList(),
    mora: mora + levelUpMora,
    expTotal: expTotal,
    levelUpMaterials: levelUpMaterials,
  );
}

List<AscensionStageInfo> getAscensionStageInfos(List<PromoteStage> promotes) {
  final filtered =
      promotes.where((p) => p.promoteLevel > 0).toList()
        ..sort((a, b) => a.unlockMaxLevel.compareTo(b.unlockMaxLevel));
  return filtered
      .map(
        (p) => AscensionStageInfo(
          level: p.unlockMaxLevel,
          promoteLevel: p.promoteLevel,
          requiresAscension: true,
          materials:
              p.costItems.entries
                  .map((e) => MaterialCost(materialId: e.key, count: e.value))
                  .toList(),
          mora: p.coinCost,
          requiredPlayerLevel: p.requiredPlayerLevel,
        ),
      )
      .toList();
}

int getAscensionForLevel(int level, List<PromoteStage> promotes) =>
    getRequiredPromoteLevel(snapToLevelMark(level), promotes);

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
