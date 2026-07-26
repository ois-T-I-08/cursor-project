import '../daily_materials/daily_material_models.dart';
import '../level_config.dart';
import '../weapon_exp.dart';
import 'ley_line_overflow.dart';
import 'resin_farm_cost_table.dart';
import 'resin_farm_estimate.dart';
import 'upgrade_option.dart';

/// 素材1行（必要・所持・不足・入手先）。
class FarmMaterialLine {
  const FarmMaterialLine({
    required this.materialId,
    required this.name,
    required this.needed,
    required this.owned,
    required this.shortage,
    this.sourceLabel,
  });

  final String materialId;
  final String name;
  final int needed;
  final int owned;
  final int shortage;
  final String? sourceLabel;
}

enum FarmEstimateMode {
  /// 期待値ベースの目安
  expected,

  /// 最低〜最大ドロップの幅
  range,
}

/// コンテンツ種別ごとの樹脂・周回見積もり。
class FarmContentSection {
  const FarmContentSection({
    required this.kind,
    required this.title,
    required this.contentLabel,
    required this.resinTotal,
    required this.runsExpected,
    required this.estimateMode,
    required this.rationale,
    this.runsMin,
    this.runsMax,
    this.resinMin,
    this.resinMax,
    this.openWeekdays = const [],
    this.openWeekdayLabels = const [],
    this.materials = const [],
    this.weeksMin,
    this.weeksMax,
    this.leyLineOverflow,
  });

  final ResinFarmKind kind;
  final String title;
  final String contentLabel;
  final int resinTotal;
  final int runsExpected;
  final FarmEstimateMode estimateMode;
  final String rationale;
  final int? runsMin;
  final int? runsMax;
  final int? resinMin;
  final int? resinMax;
  final List<int> openWeekdays;
  final List<String> openWeekdayLabels;
  final List<FarmMaterialLine> materials;
  final int? weeksMin;
  final int? weeksMax;

  /// 地脈の奔流ボーナス内訳（経験値・モラ地脈のみ）。
  final LeyLineOverflowBreakdown? leyLineOverflow;

  bool get showLeyLineOverflowBadge => leyLineOverflow != null;
}

/// 1キャラ（または複数キャラ合算）の詳細ファーミング計画。
class CharacterFarmPlan {
  const CharacterFarmPlan({
    required this.characterId,
    required this.totalResin,
    required this.naturalRegenDays,
    required this.condensedResinCount,
    required this.sections,
    this.zeroResinMaterials = const [],
  });

  final String characterId;
  final int totalResin;
  final int naturalRegenDays;
  final int condensedResinCount;
  final List<FarmContentSection> sections;
  final List<FarmMaterialLine> zeroResinMaterials;

  bool get hasLeyLineOverflow =>
      sections.any((s) => s.leyLineOverflow != null);
}

/// UpgradeOption 群から詳細ファーミング計画を構築する。
CharacterFarmPlan buildCharacterFarmPlan({
  required String characterId,
  required List<UpgradeOption> options,
  required ResinFarmCostTable table,
  Map<String, DailyMaterialSeries> materialIndex = const {},
  Map<String, String> materialCategories = const {},
  Map<String, String> materialNames = const {},
  LeyLineOverflowStatus leyLineOverflowStatus = LeyLineOverflowStatus.inactive,
  required DateTime nowUtc,
}) {
  final clock = nowUtc.toUtc();
  final needed = <String, int>{};
  final owned = <String, int>{};
  var moraNeeded = 0;

  for (final opt in options) {
    final useInv =
        opt.inventoryStatus == InventoryStatus.ownedSufficient ||
        opt.inventoryStatus == InventoryStatus.ownedInsufficient;
    for (final e in opt.materialsCost.entries) {
      needed[e.key] = (needed[e.key] ?? 0) + e.value;
    }
    for (final e in opt.expItemCost.entries) {
      needed[e.key] = (needed[e.key] ?? 0) + e.value;
    }
    moraNeeded += opt.moraCost;
    if (useInv) {
      for (final e in opt.ownedMaterials.entries) {
        final prev = owned[e.key] ?? 0;
        if (e.value > prev) owned[e.key] = e.value;
      }
    }
  }

  // Cap owned at needed for display of direct materials; synthesis may use
  // owned of lower tiers beyond this map's needed keys.
  for (final id in needed.keys) {
    final n = needed[id]!;
    final o = owned[id] ?? 0;
    owned[id] = o > n ? n : o;
  }

  final shortage = <String, int>{
    for (final e in needed.entries)
      e.key: (e.value - (owned[e.key] ?? 0)).clamp(0, e.value),
  };

  final sections = <FarmContentSection>[];
  final zeroLines = <FarmMaterialLine>[];

  // ── EXP books (ley line) ──────────────────────────────────────────
  final expSection = _buildExpSection(
    shortage: shortage,
    needed: needed,
    owned: owned,
    table: table,
    materialNames: materialNames,
    overflowStatus: leyLineOverflowStatus,
    nowUtc: clock,
  );
  if (expSection != null) sections.add(expSection);

  // ── Mora ──────────────────────────────────────────────────────────
  final moraSection = _buildMoraSection(
    moraNeeded: moraNeeded,
    table: table,
    overflowStatus: leyLineOverflowStatus,
    nowUtc: clock,
  );
  if (moraSection != null) sections.add(moraSection);

  // ── Series-based (talent / weapon) with synthesis ─────────────────
  final covered = <String>{};
  for (final bookId in expBooks.map((b) => b.id)) {
    covered.add(bookId);
  }
  for (final ore in weaponEnhancementOres) {
    covered.add(ore.id);
  }

  final seriesGroups = <String, DailyMaterialSeries>{};
  for (final id in shortage.keys) {
    final series = materialIndex[id];
    if (series == null) continue;
    if (series.kind != DailyMaterialKind.talentBook &&
        series.kind != DailyMaterialKind.weaponAscension) {
      continue;
    }
    seriesGroups.putIfAbsent(series.id, () => series);
  }

  for (final series in seriesGroups.values) {
    final section = _buildSeriesSection(
      series: series,
      needed: needed,
      owned: owned,
      shortage: shortage,
      table: table,
      materialNames: materialNames,
    );
    if (section != null) {
      sections.add(section);
      covered.addAll(series.materialIds);
    }
  }

  // ── Weekly / world boss / artifact / other by kind ────────────────
  final byKind = <ResinFarmKind, List<String>>{};
  for (final e in shortage.entries) {
    if (e.value <= 0 || covered.contains(e.key)) continue;
    final kind = classifyResinFarmKind(
      materialId: e.key,
      table: table,
      materialIndex: materialIndex,
      materialCategories: materialCategories,
    );
    if (kind == ResinFarmKind.zeroResin || kind == ResinFarmKind.unknown) {
      if (e.value > 0 && kind == ResinFarmKind.zeroResin) {
        zeroLines.add(
          FarmMaterialLine(
            materialId: e.key,
            name: materialNames[e.key] ?? e.key,
            needed: needed[e.key] ?? e.value,
            owned: owned[e.key] ?? 0,
            shortage: e.value,
            sourceLabel: '樹脂不要',
          ),
        );
      }
      continue;
    }
    if (kind == ResinFarmKind.leyLineExp || kind == ResinFarmKind.leyLineMora) {
      continue;
    }
    if (kind == ResinFarmKind.talentDomain ||
        kind == ResinFarmKind.weaponDomain) {
      // Already handled via series; leftover without series index
      byKind.putIfAbsent(kind, () => []).add(e.key);
      continue;
    }
    byKind.putIfAbsent(kind, () => []).add(e.key);
  }

  for (final entry in byKind.entries) {
    final section = _buildFlatKindSection(
      kind: entry.key,
      materialIds: entry.value,
      needed: needed,
      owned: owned,
      shortage: shortage,
      table: table,
      materialIndex: materialIndex,
      materialNames: materialNames,
    );
    if (section != null) sections.add(section);
  }

  // Stable category order
  const order = [
    ResinFarmKind.leyLineExp,
    ResinFarmKind.leyLineMora,
    ResinFarmKind.talentDomain,
    ResinFarmKind.weaponDomain,
    ResinFarmKind.worldBoss,
    ResinFarmKind.weeklyBoss,
    ResinFarmKind.artifactDomain,
  ];
  sections.sort(
    (a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)),
  );

  final totalResin = sections.fold<int>(0, (s, x) => s + x.resinTotal);
  final day = table.meta.naturalResinPerDay;
  final condensed = table.meta.condensedResinValue;
  return CharacterFarmPlan(
    characterId: characterId,
    totalResin: totalResin,
    naturalRegenDays: totalResin <= 0 ? 0 : (totalResin / day).ceil(),
    condensedResinCount:
        totalResin <= 0 ? 0 : (totalResin / condensed).ceil(),
    sections: sections,
    zeroResinMaterials: zeroLines
      ..sort((a, b) => a.name.compareTo(b.name)),
  );
}

/// 複数キャラの計画を素材集約して再計算する。
CharacterFarmPlan mergeCharacterFarmPlans({
  required List<UpgradeOption> allOptions,
  required ResinFarmCostTable table,
  Map<String, DailyMaterialSeries> materialIndex = const {},
  Map<String, String> materialCategories = const {},
  Map<String, String> materialNames = const {},
  LeyLineOverflowStatus leyLineOverflowStatus = LeyLineOverflowStatus.inactive,
  required DateTime nowUtc,
}) {
  return buildCharacterFarmPlan(
    characterId: '_aggregate',
    options: allOptions,
    table: table,
    materialIndex: materialIndex,
    materialCategories: materialCategories,
    materialNames: materialNames,
    leyLineOverflowStatus: leyLineOverflowStatus,
    nowUtc: nowUtc,
  );
}

// ── helpers ─────────────────────────────────────────────────────────

FarmContentSection? _buildExpSection({
  required Map<String, int> shortage,
  required Map<String, int> needed,
  required Map<String, int> owned,
  required ResinFarmCostTable table,
  required Map<String, String> materialNames,
  required LeyLineOverflowStatus overflowStatus,
  required DateTime nowUtc,
}) {
  final cost = table.costFor(ResinFarmKind.leyLineExp);
  if (cost == null) return null;

  var totalExpShortage = 0;
  final lines = <FarmMaterialLine>[];
  for (final book in expBooks) {
    final s = shortage[book.id] ?? 0;
    if (s <= 0) continue;
    totalExpShortage += s * book.exp;
    lines.add(
      FarmMaterialLine(
        materialId: book.id,
        name: materialNames[book.id] ?? book.name,
        needed: needed[book.id] ?? s,
        owned: owned[book.id] ?? 0,
        shortage: s,
        sourceLabel: cost.contentLabel ?? '地脈の花（経験値）',
      ),
    );
  }
  // Weapon ores → treat as ley line exp equivalent via ore EXP
  for (final ore in weaponEnhancementOres) {
    final s = shortage[ore.id] ?? 0;
    if (s <= 0) continue;
    totalExpShortage += s * ore.exp;
    lines.add(
      FarmMaterialLine(
        materialId: ore.id,
        name: materialNames[ore.id] ?? ore.name,
        needed: needed[ore.id] ?? s,
        owned: owned[ore.id] ?? 0,
        shortage: s,
        sourceLabel: cost.contentLabel ?? '地脈の花（経験値）',
      ),
    );
  }
  if (totalExpShortage <= 0) return null;

  final heroExp = expBooks.firstWhere((b) => b.id == '104003').exp;
  final heroEquiv = totalExpShortage / heroExp;
  final perRun = cost.assumedHeroWitEquivalentPerRun ??
      cost.assumedDropsPerRun ??
      1.0;
  final normalRuns = (heroEquiv / perRun).ceil();
  final label = cost.contentLabel ?? '地脈の花（経験値）';

  final overflow = applyLeyLineOverflowBonus(
    normalEquivalentRuns: normalRuns,
    resinPerRun: cost.resinPerRun,
    status: overflowStatus,
    leyLineType: LeyLineOverflowLeyLineType.exp,
    nowUtc: nowUtc,
  );
  final runs = overflow?.actualRuns ?? normalRuns;
  final resin = overflow?.resinTotal ?? (runs * cost.resinPerRun);
  final rationale = overflow == null
      ? '不足経験値を大英雄の経験相当へ換算し、1回あたり約$perRun冊相当で切り上げ。'
      : overflow.isMaxEstimate
          ? '通常換算 $normalRuns 回分。ボーナスは最大適用時の目安（使用済み回数不明）。'
          : '通常換算 $normalRuns 回分。当日ボーナス残り ${overflow.remainingBonusCapacity} 回を反映。';

  return FarmContentSection(
    kind: ResinFarmKind.leyLineExp,
    title: '経験値本',
    contentLabel: label,
    resinTotal: resin,
    runsExpected: runs,
    estimateMode: FarmEstimateMode.expected,
    rationale: rationale,
    materials: lines,
    leyLineOverflow: overflow,
  );
}

FarmContentSection? _buildMoraSection({
  required int moraNeeded,
  required ResinFarmCostTable table,
  required LeyLineOverflowStatus overflowStatus,
  required DateTime nowUtc,
}) {
  if (moraNeeded <= 0) return null;
  final cost = table.costFor(ResinFarmKind.leyLineMora);
  if (cost == null) return null;
  final perRun = cost.assumedMoraPerRun ?? 60000;
  final normalRuns = (moraNeeded / perRun).ceil();
  final label = cost.contentLabel ?? 'モラ地脈';

  final overflow = applyLeyLineOverflowBonus(
    normalEquivalentRuns: normalRuns,
    resinPerRun: cost.resinPerRun,
    status: overflowStatus,
    leyLineType: LeyLineOverflowLeyLineType.mora,
    nowUtc: nowUtc,
  );
  final runs = overflow?.actualRuns ?? normalRuns;
  final resin = overflow?.resinTotal ?? (runs * cost.resinPerRun);
  final rationale = overflow == null
      ? '不足モラ $moraNeeded を1回あたり $perRun で切り上げ。'
      : overflow.isMaxEstimate
          ? '通常換算 $normalRuns 回分。ボーナスは最大適用時の目安（使用済み回数不明）。'
          : '通常換算 $normalRuns 回分。当日ボーナス残り ${overflow.remainingBonusCapacity} 回を反映。';

  return FarmContentSection(
    kind: ResinFarmKind.leyLineMora,
    title: 'モラ',
    contentLabel: label,
    resinTotal: resin,
    runsExpected: runs,
    estimateMode: FarmEstimateMode.expected,
    rationale: rationale,
    materials: [
      FarmMaterialLine(
        materialId: '__mora__',
        name: 'モラ',
        needed: moraNeeded,
        owned: 0,
        shortage: moraNeeded,
        sourceLabel: label,
      ),
    ],
    leyLineOverflow: overflow,
  );
}

FarmContentSection? _buildSeriesSection({
  required DailyMaterialSeries series,
  required Map<String, int> needed,
  required Map<String, int> owned,
  required Map<String, int> shortage,
  required ResinFarmCostTable table,
  required Map<String, String> materialNames,
}) {
  final kind = series.kind == DailyMaterialKind.talentBook
      ? ResinFarmKind.talentDomain
      : ResinFarmKind.weaponDomain;
  final cost = table.costFor(kind);
  if (cost == null) return null;

  final ratio = table.meta.synthesisRatio;
  final ids = series.materialIds;
  if (ids.isEmpty) return null;

  var neededUnits = 0;
  var ownedUnits = 0;
  final lines = <FarmMaterialLine>[];
  for (var i = 0; i < ids.length; i++) {
    final id = ids[i];
    final weight = _powInt(ratio, i);
    final n = needed[id] ?? 0;
    final o = owned[id] ?? 0;
    final s = shortage[id] ?? 0;
    if (n <= 0 && s <= 0) continue;
    neededUnits += n * weight;
    ownedUnits += o * weight;
    lines.add(
      FarmMaterialLine(
        materialId: id,
        name: materialNames[id] ?? id,
        needed: n,
        owned: o,
        shortage: s,
        sourceLabel: '「${series.name}」',
      ),
    );
  }
  final shortageUnits = (neededUnits - ownedUnits).clamp(0, neededUnits);
  if (shortageUnits <= 0) return null;

  final drops = cost.assumedDropsPerRun ?? 1.0;
  // Normalize drops to base units of the highest tier in series:
  // assumedDropsPerRun is treated as highest-tier equivalent, convert to base.
  final highestWeight = _powInt(ratio, ids.length - 1);
  final dropsInBase = drops * highestWeight;
  final runs = (shortageUnits / dropsInBase).ceil();
  final resin = runs * cost.resinPerRun;
  final content = cost.contentLabel ??
      (kind == ResinFarmKind.talentDomain ? '熟知秘境' : '煉武秘境');
  final openWeekdays = [
    for (var d = 1; d <= 7; d++)
      if (series.isAvailableOn(d)) d,
  ];
  final dayLabels = [
    for (final d in openWeekdays)
      if (d >= 1 && d <= 7) table.meta.weekdayLabels[d - 1],
  ];

  return FarmContentSection(
    kind: kind,
    title: kind == ResinFarmKind.talentDomain ? '天賦素材' : '武器突破素材',
    contentLabel: '$content「${series.name}」',
    resinTotal: resin,
    runsExpected: runs,
    estimateMode: FarmEstimateMode.expected,
    rationale:
        '合成比 $ratio:1 で共通単位へ正規化し、1回あたり最高レア約$drops個相当で切り上げ。',
    openWeekdays: openWeekdays,
    openWeekdayLabels: dayLabels,
    materials: lines,
  );
}

FarmContentSection? _buildFlatKindSection({
  required ResinFarmKind kind,
  required List<String> materialIds,
  required Map<String, int> needed,
  required Map<String, int> owned,
  required Map<String, int> shortage,
  required ResinFarmCostTable table,
  required Map<String, DailyMaterialSeries> materialIndex,
  required Map<String, String> materialNames,
}) {
  final cost = table.costFor(kind);
  if (cost == null) return null;

  final lines = <FarmMaterialLine>[];
  var totalShortage = 0;
  for (final id in materialIds) {
    final s = shortage[id] ?? 0;
    if (s <= 0) continue;
    totalShortage += s;
    final series = materialIndex[id];
    lines.add(
      FarmMaterialLine(
        materialId: id,
        name: materialNames[id] ?? id,
        needed: needed[id] ?? s,
        owned: owned[id] ?? 0,
        shortage: s,
        sourceLabel: series?.name ?? cost.contentLabel,
      ),
    );
  }
  if (totalShortage <= 0) return null;

  final expectedDrops = cost.assumedDropsPerRun ?? 1.0;
  final runsExpected = (totalShortage / expectedDrops).ceil();
  var runsMin = runsExpected;
  var runsMax = runsExpected;
  var mode = FarmEstimateMode.expected;
  if (cost.hasDropRange) {
    mode = FarmEstimateMode.range;
    runsMin = (totalShortage / cost.assumedDropsPerRunMax!).ceil();
    runsMax = (totalShortage / cost.assumedDropsPerRunMin!).ceil();
    if (runsMin > runsMax) {
      final t = runsMin;
      runsMin = runsMax;
      runsMax = t;
    }
  }

  final resinExpected = runsExpected * cost.resinPerRun;
  final resinMin = runsMin * cost.resinPerRun;
  final resinMax = runsMax * cost.resinPerRun;
  final label = cost.contentLabel ?? kind.name;

  int? weeksMin;
  int? weeksMax;
  final perWeek = cost.challengesPerWeek;
  if (kind == ResinFarmKind.weeklyBoss && perWeek != null && perWeek > 0) {
    weeksMin = (runsMin / perWeek).ceil();
    weeksMax = (runsMax / perWeek).ceil();
  }

  final title = switch (kind) {
    ResinFarmKind.worldBoss => '突破素材',
    ResinFarmKind.weeklyBoss => '週ボス素材',
    ResinFarmKind.artifactDomain => '聖遺物',
    ResinFarmKind.talentDomain => '天賦素材',
    ResinFarmKind.weaponDomain => '武器突破素材',
    _ => label,
  };

  final rationale = mode == FarmEstimateMode.range
      ? 'ドロップ ${cost.assumedDropsPerRunMin}〜${cost.assumedDropsPerRunMax}個/回の推定。目安は期待値 $expectedDrops個/回。'
      : '1回あたり約$expectedDrops個の目安で切り上げ。';

  return FarmContentSection(
    kind: kind,
    title: title,
    contentLabel: label,
    resinTotal: resinExpected,
    runsExpected: runsExpected,
    runsMin: mode == FarmEstimateMode.range ? runsMin : null,
    runsMax: mode == FarmEstimateMode.range ? runsMax : null,
    resinMin: mode == FarmEstimateMode.range ? resinMin : null,
    resinMax: mode == FarmEstimateMode.range ? resinMax : null,
    estimateMode: mode,
    rationale: rationale,
    materials: lines,
    weeksMin: weeksMin,
    weeksMax: weeksMax,
  );
}

int _powInt(int base, int exp) {
  var r = 1;
  for (var i = 0; i < exp; i++) {
    r *= base;
  }
  return r;
}
