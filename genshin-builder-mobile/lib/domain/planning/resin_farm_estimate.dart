import '../daily_materials/daily_material_models.dart';
import '../level_config.dart';
import '../weapon_exp.dart';
import 'resin_farm_cost_table.dart';
import 'upgrade_option.dart';

/// UpgradeOption の必要素材から樹脂概算を算出する。
int estimateResinCostForUpgradeOption({
  required UpgradeOption option,
  required ResinFarmCostTable table,
  Map<String, DailyMaterialSeries> materialIndex = const {},
  Map<String, String> materialCategories = const {},
}) {
  final useRemaining =
      option.inventoryStatus == InventoryStatus.ownedSufficient ||
      option.inventoryStatus == InventoryStatus.ownedInsufficient;

  final neededMats = <String, int>{};
  if (useRemaining) {
    for (final e in option.remainingMaterials.entries) {
      if (e.value > 0) neededMats[e.key] = e.value;
    }
    for (final e in option.expItemCost.entries) {
      final owned = option.ownedMaterials[e.key] ?? 0;
      final rem = e.value - owned;
      if (rem > 0) neededMats[e.key] = (neededMats[e.key] ?? 0) + rem;
    }
  } else {
    neededMats.addAll(option.materialsCost);
    for (final e in option.expItemCost.entries) {
      neededMats[e.key] = (neededMats[e.key] ?? 0) + e.value;
    }
  }

  var resin = 0;
  var expShortage = 0;
  for (final e in neededMats.entries) {
    if (e.value <= 0) continue;
    final kind = classifyResinFarmKind(
      materialId: e.key,
      table: table,
      materialIndex: materialIndex,
      materialCategories: materialCategories,
    );
    if (kind == ResinFarmKind.leyLineExp) {
      final bookExp = _expForMaterialId(e.key);
      if (bookExp != null) {
        expShortage += e.value * bookExp;
        continue;
      }
    }
    resin += _resinForCount(kind: kind, count: e.value, table: table);
  }
  if (expShortage > 0) {
    final cost = table.costFor(ResinFarmKind.leyLineExp);
    if (cost != null) {
      final heroExp = expBooks.firstWhere((b) => b.id == '104003').exp;
      final perRun = cost.assumedHeroWitEquivalentPerRun ??
          cost.assumedDropsPerRun ??
          1.0;
      if (perRun > 0) {
        final runs = ((expShortage / heroExp) / perRun).ceil();
        resin += runs * cost.resinPerRun;
      }
    }
  }

  final moraNeeded = useRemaining
      ? _remainingMora(option)
      : option.moraCost;
  if (moraNeeded > 0) {
    resin += _resinForMora(moraNeeded, table);
  }

  return resin;
}

ResinFarmKind classifyResinFarmKind({
  required String materialId,
  required ResinFarmCostTable table,
  Map<String, DailyMaterialSeries> materialIndex = const {},
  Map<String, String> materialCategories = const {},
}) {
  final series = materialIndex[materialId];
  if (series != null) {
    return switch (series.kind) {
      DailyMaterialKind.talentBook => ResinFarmKind.talentDomain,
      DailyMaterialKind.weaponAscension => ResinFarmKind.weaponDomain,
      DailyMaterialKind.artifactDomain => ResinFarmKind.artifactDomain,
      DailyMaterialKind.weeklyBoss => ResinFarmKind.weeklyBoss,
    };
  }

  if (_expBookIds.contains(materialId) || _weaponOreIds.contains(materialId)) {
    return ResinFarmKind.leyLineExp;
  }

  final category = materialCategories[materialId];
  if (category != null && table.zeroResinCategories.contains(category)) {
    return ResinFarmKind.zeroResin;
  }
  if (category == 'characterLevelUpMaterial' ||
      category == 'characterAscensionMaterial') {
    return ResinFarmKind.worldBoss;
  }
  if (category == 'characterEXPMaterial' ||
      category == 'weaponEnhancementMaterial') {
    return ResinFarmKind.leyLineExp;
  }
  if (category == 'characterTalentMaterial') {
    return ResinFarmKind.talentDomain;
  }
  if (category == 'weaponAscensionMaterial') {
    return ResinFarmKind.weaponDomain;
  }

  return ResinFarmKind.unknown;
}

int _resinForCount({
  required ResinFarmKind kind,
  required int count,
  required ResinFarmCostTable table,
}) {
  if (kind == ResinFarmKind.zeroResin || kind == ResinFarmKind.unknown) {
    return 0;
  }
  if (kind == ResinFarmKind.leyLineMora || kind == ResinFarmKind.leyLineExp) {
    return 0;
  }
  final cost = table.costFor(kind);
  if (cost == null) return 0;
  final drops = cost.assumedDropsPerRun;
  if (drops == null || drops <= 0) return 0;
  final runs = (count / drops).ceil();
  return runs * cost.resinPerRun;
}

int _resinForMora(int mora, ResinFarmCostTable table) {
  final cost = table.costFor(ResinFarmKind.leyLineMora);
  if (cost == null) return 0;
  final perRun = cost.assumedMoraPerRun;
  if (perRun == null || perRun <= 0) return 0;
  final runs = (mora / perRun).ceil();
  return runs * cost.resinPerRun;
}

int _remainingMora(UpgradeOption option) {
  // Mora is not tracked in remainingMaterials; approximate with full moraCost
  // when inventory is set (conservative — may overestimate slightly).
  return option.moraCost;
}

final _expBookIds = {for (final b in expBooks) b.id};
final _weaponOreIds = {for (final o in weaponEnhancementOres) o.id};

int? _expForMaterialId(String id) {
  for (final b in expBooks) {
    if (b.id == id) return b.exp;
  }
  for (final o in weaponEnhancementOres) {
    if (o.id == id) return o.exp;
  }
  return null;
}
