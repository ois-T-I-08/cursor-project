import '../models/master_models.dart';
import '../level_config.dart';
import '../level_progression.dart';
import '../material_requirements.dart';
import '../models/calculation_models.dart';
import '../talent_progression.dart';
import 'daily_material_models.dart';

/// 表示順（片手剣→両手剣→長柄→弓→法器）
const dailyWeaponTypeOrder = [
  'sword',
  'claymore',
  'polearm',
  'bow',
  'catalyst',
];

const dailyWeaponTypeLabels = <String, String>{
  'sword': '片手剣',
  'claymore': '両手剣',
  'polearm': '長柄武器',
  'bow': '弓',
  'catalyst': '法器',
};

/// 天賦 upgrade から使用素材 ID を抽出
Set<String> materialIdsFromTalents(
  Map<String, List<TalentLevelUpgrade>> talents,
) {
  final ids = <String>{};
  for (final upgrades in talents.values) {
    for (final u in upgrades) {
      ids.addAll(u.costItems.keys);
    }
  }
  return ids;
}

/// 武器突破から使用素材 ID を抽出
Set<String> materialIdsFromPromotes(List<PromoteStage> promotes) {
  final ids = <String>{};
  for (final p in promotes) {
    ids.addAll(p.costItems.keys);
  }
  return ids;
}

/// キャラ入力
class CharacterTalentCatalogEntry {
  const CharacterTalentCatalogEntry({
    required this.character,
    required this.talentMaterialIds,
    this.progress,
    this.talents = const {},
    this.isOwned = false,
    this.isBuilding = false,
  });

  final MasterCharacter character;
  final Set<String> talentMaterialIds;
  final UserProgress? progress;
  final Map<String, List<TalentLevelUpgrade>> talents;
  final bool isOwned;
  final bool isBuilding;
}

/// 武器入力
class WeaponAscensionCatalogEntry {
  const WeaponAscensionCatalogEntry({
    required this.weapon,
    required this.ascensionMaterialIds,
    this.weaponLevel,
    this.weaponRefinement,
    this.promotes = const [],
    this.equippedCharacters = const [],
    this.isOwned = false,
    this.isBuilding = false,
  });

  final MasterWeapon weapon;
  final Set<String> ascensionMaterialIds;
  final int? weaponLevel;
  final int? weaponRefinement;
  final List<PromoteStage> promotes;
  final List<DailyEquippedCharacter> equippedCharacters;
  final bool isOwned;
  final bool isBuilding;
}

int _ownershipRank({required bool isOwned, required bool isBuilding}) {
  if (isOwned) return 0;
  if (isBuilding) return 1;
  return 2;
}

int _shortageRank(DailyRemainingStatus status, int remaining) {
  if (status == DailyRemainingStatus.needed && remaining > 0) return 0;
  if (status == DailyRemainingStatus.complete) return 1;
  return 2; // unknown
}

/// キャラ優先: 所持 → 育成中 → 未所持、その中で不足多い順
int compareDailyCharacterConsumers(
  DailyMaterialConsumer a,
  DailyMaterialConsumer b,
) {
  final byOwn = _ownershipRank(isOwned: a.isOwned, isBuilding: a.isBuilding)
      .compareTo(
        _ownershipRank(isOwned: b.isOwned, isBuilding: b.isBuilding),
      );
  if (byOwn != 0) return byOwn;

  final byShort = _shortageRank(a.remainingStatus, a.remainingCount).compareTo(
    _shortageRank(b.remainingStatus, b.remainingCount),
  );
  if (byShort != 0) return byShort;

  final byNeed = b.remainingCount.compareTo(a.remainingCount);
  if (byNeed != 0) return byNeed;

  final byRarity = (b.rarity ?? 0).compareTo(a.rarity ?? 0);
  if (byRarity != 0) return byRarity;
  return a.name.compareTo(b.name);
}

/// 武器優先: 所持 → 装備中 → 育成予定 → 未所持、育成途中を上位
int compareDailyWeaponConsumers(
  DailyMaterialConsumer a,
  DailyMaterialConsumer b,
) {
  final byOwn = _ownershipRank(isOwned: a.isOwned, isBuilding: a.isBuilding)
      .compareTo(
        _ownershipRank(isOwned: b.isOwned, isBuilding: b.isBuilding),
      );
  if (byOwn != 0) return byOwn;

  final byEquip = (b.isEquipped ? 1 : 0).compareTo(a.isEquipped ? 1 : 0);
  if (byEquip != 0) return byEquip;

  final byBuilding = (b.isBuilding ? 1 : 0).compareTo(a.isBuilding ? 1 : 0);
  if (byBuilding != 0) return byBuilding;

  final aInProgress = a.hasShortage ||
      (a.weaponLevel != null && a.weaponLevel! < levelMax) ||
      (a.weaponRefinement != null && a.weaponRefinement! < 5);
  final bInProgress = b.hasShortage ||
      (b.weaponLevel != null && b.weaponLevel! < levelMax) ||
      (b.weaponRefinement != null && b.weaponRefinement! < 5);
  final byProgress = (bInProgress ? 1 : 0).compareTo(aInProgress ? 1 : 0);
  if (byProgress != 0) return byProgress;

  final byShort = _shortageRank(a.remainingStatus, a.remainingCount).compareTo(
    _shortageRank(b.remainingStatus, b.remainingCount),
  );
  if (byShort != 0) return byShort;

  final byNeed = b.remainingCount.compareTo(a.remainingCount);
  if (byNeed != 0) return byNeed;

  final byRarity = (b.rarity ?? 0).compareTo(a.rarity ?? 0);
  if (byRarity != 0) return byRarity;
  return a.name.compareTo(b.name);
}

({
  DailyRemainingStatus status,
  int count,
  Map<String, int> byMaterial,
  Map<String, int> nextByMaterial,
}) _talentRemainingForSeries({
  required String seriesId,
  required Map<String, DailyMaterialSeries> materialIndex,
  required CharacterTalentCatalogEntry entry,
  required int talentTargetLevel,
}) {
  final progress = entry.progress;
  if (progress == null || entry.talents.isEmpty) {
    return (
      status: DailyRemainingStatus.unknown,
      count: 0,
      byMaterial: const <String, int>{},
      nextByMaterial: const <String, int>{},
    );
  }

  final byMaterial = <String, int>{};
  final nextByMaterial = <String, int>{};

  void addSeriesCost(Map<String, int> target, String materialId, int count) {
    final series = materialIndex[materialId];
    if (series?.id != seriesId) return;
    target[materialId] = (target[materialId] ?? 0) + count;
  }

  void addTalent(String key, int current) {
    final upgrades = entry.talents[key];
    if (upgrades == null || upgrades.isEmpty) return;
    final lines = getRangeTalentRequirements(
      current,
      talentTargetLevel,
      talentLevelMax,
      upgrades,
    );
    for (final line in lines) {
      if (line.isMora) continue;
      addSeriesCost(byMaterial, line.materialId, line.count);
    }

    final next = getNextTalentRequirements(
      current,
      talentLevelMax,
      upgrades,
    );
    if (next == null) return;
    for (final m in next.materials) {
      addSeriesCost(nextByMaterial, m.materialId, m.count);
    }
  }

  addTalent('skill_0', progress.talentNormal);
  addTalent('skill_1', progress.talentSkill);
  addTalent('skill_2', progress.talentBurst);

  final remaining = byMaterial.values.fold(0, (s, n) => s + n);
  if (remaining > 0) {
    return (
      status: DailyRemainingStatus.needed,
      count: remaining,
      byMaterial: byMaterial,
      nextByMaterial: nextByMaterial,
    );
  }
  return (
    status: DailyRemainingStatus.complete,
    count: 0,
    byMaterial: const <String, int>{},
    nextByMaterial: const <String, int>{},
  );
}

({
  DailyRemainingStatus status,
  int count,
  Map<String, int> byMaterial,
  Map<String, int> nextByMaterial,
}) _weaponRemainingForSeries({
  required String seriesId,
  required Map<String, DailyMaterialSeries> materialIndex,
  required WeaponAscensionCatalogEntry entry,
  required int weaponTargetLevel,
}) {
  final level = entry.weaponLevel;
  if (level == null || entry.promotes.isEmpty) {
    return (
      status: DailyRemainingStatus.unknown,
      count: 0,
      byMaterial: const <String, int>{},
      nextByMaterial: const <String, int>{},
    );
  }
  if (level >= weaponTargetLevel) {
    return (
      status: DailyRemainingStatus.complete,
      count: 0,
      byMaterial: const <String, int>{},
      nextByMaterial: const <String, int>{},
    );
  }

  final byMaterial = <String, int>{};
  final nextByMaterial = <String, int>{};

  void addSeriesCost(Map<String, int> target, String materialId, int count) {
    final series = materialIndex[materialId];
    if (series?.id != seriesId) return;
    target[materialId] = (target[materialId] ?? 0) + count;
  }

  final lines = getRangeLevelRequirements(
    level,
    weaponTargetLevel,
    entry.promotes,
    'weapon',
    weaponRarity: entry.weapon.rarity,
  );
  for (final line in lines) {
    if (line.isMora) continue;
    addSeriesCost(byMaterial, line.materialId, line.count);
  }

  final next = getNextStageRequirements(
    level,
    entry.promotes,
    'weapon',
    entry.weapon.rarity,
  );
  if (next != null) {
    for (final m in next.materials) {
      addSeriesCost(nextByMaterial, m.materialId, m.count);
    }
  }

  final remaining = byMaterial.values.fold(0, (s, n) => s + n);
  if (remaining > 0) {
    return (
      status: DailyRemainingStatus.needed,
      count: remaining,
      byMaterial: byMaterial,
      nextByMaterial: nextByMaterial,
    );
  }
  return (
    status: DailyRemainingStatus.complete,
    count: 0,
    byMaterial: const <String, int>{},
    nextByMaterial: const <String, int>{},
  );
}

/// 曜日スケジュール × マスタ紐づけから表示用プランを構築する純関数
DailyMaterialsPlan buildDailyMaterialsPlan({
  required DailyMaterialSchedule schedule,
  required int weekday,
  required Map<String, MasterMaterial> materials,
  required List<CharacterTalentCatalogEntry> characters,
  required List<WeaponAscensionCatalogEntry> weapons,
  int talentTargetLevel = talentLevelMax,
  int weaponTargetLevel = levelMax,
}) {
  final materialIndex = schedule.buildMaterialIndex();
  final talentBySeries = <String, List<DailyMaterialConsumer>>{};
  final weaponBySeries = <String, List<DailyMaterialConsumer>>{};

  for (final entry in characters) {
    final seriesIds = <String>{};
    for (final materialId in entry.talentMaterialIds) {
      final series = materialIndex[materialId];
      if (series != null && series.kind == DailyMaterialKind.talentBook) {
        seriesIds.add(series.id);
      }
    }
    for (final seriesId in seriesIds) {
      final rem = _talentRemainingForSeries(
        seriesId: seriesId,
        materialIndex: materialIndex,
        entry: entry,
        talentTargetLevel: talentTargetLevel,
      );
      talentBySeries.putIfAbsent(seriesId, () => []).add(
            DailyMaterialConsumer(
              id: entry.character.id,
              name: entry.character.name,
              iconUrl: entry.character.iconUrl,
              remainingStatus: rem.status,
              remainingCount: rem.count,
              remainingByMaterialId: rem.byMaterial,
              nextStageByMaterialId: rem.nextByMaterial,
              isOwned: entry.isOwned,
              isBuilding: entry.isBuilding,
              rarity: entry.character.rarity,
            ),
          );
    }
  }

  for (final entry in weapons) {
    final seriesIds = <String>{};
    for (final materialId in entry.ascensionMaterialIds) {
      final series = materialIndex[materialId];
      if (series != null && series.kind == DailyMaterialKind.weaponAscension) {
        seriesIds.add(series.id);
      }
    }
    final owned = entry.isOwned || entry.equippedCharacters.isNotEmpty;
    for (final seriesId in seriesIds) {
      final rem = _weaponRemainingForSeries(
        seriesId: seriesId,
        materialIndex: materialIndex,
        entry: entry,
        weaponTargetLevel: weaponTargetLevel,
      );
      weaponBySeries.putIfAbsent(seriesId, () => []).add(
            DailyMaterialConsumer(
              id: entry.weapon.id,
              name: entry.weapon.name,
              iconUrl: entry.weapon.iconUrl,
              remainingStatus: rem.status,
              remainingCount: rem.count,
              remainingByMaterialId: rem.byMaterial,
              nextStageByMaterialId: rem.nextByMaterial,
              isOwned: owned,
              isBuilding: entry.isBuilding,
              weaponType: entry.weapon.weaponType,
              rarity: entry.weapon.rarity,
              weaponLevel: entry.weaponLevel,
              weaponRefinement: entry.weaponRefinement,
              equippedCharacters: entry.equippedCharacters,
            ),
          );
    }
  }

  List<MasterMaterial> resolveMaterials(
    DailyMaterialSeries series,
    DailyMaterialKind kind,
  ) {
    final list = <MasterMaterial>[];
    for (final id in series.materialIds) {
      final m = materials[id];
      if (m != null) {
        list.add(m);
      } else {
        list.add(
          MasterMaterial(
            id: id,
            name: id,
            category: kind == DailyMaterialKind.talentBook
                ? 'characterTalentMaterial'
                : 'weaponAscensionMaterial',
            iconUrl: '',
          ),
        );
      }
    }
    return list;
  }

  List<DailyMaterialConsumerGroup> talentGroups(
    List<DailyMaterialConsumer> consumers,
  ) {
    if (consumers.isEmpty) return const [];
    consumers.sort(compareDailyCharacterConsumers);
    return [
      DailyMaterialConsumerGroup(
        key: 'characters',
        label: '使用キャラクター',
        consumers: consumers,
      ),
    ];
  }

  List<DailyMaterialConsumerGroup> weaponGroups(
    List<DailyMaterialConsumer> consumers,
  ) {
    if (consumers.isEmpty) return const [];
    final byType = <String, List<DailyMaterialConsumer>>{};
    for (final c in consumers) {
      final type = c.weaponType ?? 'unknown';
      byType.putIfAbsent(type, () => []).add(c);
    }
    for (final list in byType.values) {
      list.sort(compareDailyWeaponConsumers);
    }

    final keys = [
      ...dailyWeaponTypeOrder.where(byType.containsKey),
      ...byType.keys.where((k) => !dailyWeaponTypeOrder.contains(k)).toList()
        ..sort(),
    ];
    return [
      for (final key in keys)
        DailyMaterialConsumerGroup(
          key: key,
          label: dailyWeaponTypeLabels[key] ?? key,
          consumers: byType[key]!,
        ),
    ];
  }

  List<DailyMaterialSeriesCardData> cardsFor(DailyMaterialKind kind) {
    final available = schedule.seriesForDay(weekday, kind: kind);
    final source =
        kind == DailyMaterialKind.talentBook ? talentBySeries : weaponBySeries;
    final cards = <DailyMaterialSeriesCardData>[];
    for (final series in available) {
      final consumers = List<DailyMaterialConsumer>.from(
        source[series.id] ?? const [],
      );
      final groups = kind == DailyMaterialKind.talentBook
          ? talentGroups(consumers)
          : weaponGroups(consumers);
      final byMaterial = <String, int>{};
      final nextByMaterial = <String, int>{};
      for (final c in consumers) {
        if (!c.hasShortage) continue;
        for (final e in c.remainingByMaterialId.entries) {
          byMaterial[e.key] = (byMaterial[e.key] ?? 0) + e.value;
        }
        for (final e in c.nextStageByMaterialId.entries) {
          nextByMaterial[e.key] = (nextByMaterial[e.key] ?? 0) + e.value;
        }
      }
      cards.add(
        DailyMaterialSeriesCardData(
          series: series,
          materials: resolveMaterials(series, kind),
          consumerGroups: groups,
          remainingByMaterialId: byMaterial,
          nextStageByMaterialId: nextByMaterial,
        ),
      );
    }
    cards.sort((a, b) {
      final byRegion = a.series.region.compareTo(b.series.region);
      if (byRegion != 0) return byRegion;
      return a.series.name.compareTo(b.series.name);
    });
    return cards;
  }

  return DailyMaterialsPlan(
    weekday: weekday,
    talentCards: cardsFor(DailyMaterialKind.talentBook),
    weaponCards: cardsFor(DailyMaterialKind.weaponAscension),
  );
}
