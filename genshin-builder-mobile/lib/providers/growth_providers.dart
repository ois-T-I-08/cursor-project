import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account/build_account_snapshot_use_case.dart';
import '../application/account/generate_health_report_use_case.dart';
import '../application/hoyolab/sync_hoyolab_relics_to_progress_use_case.dart';
import '../application/planning/generate_daily_plan_use_case.dart';
import '../application/planning/diagnose_investment_use_case.dart';
import '../application/planning/generate_upgrade_options_use_case.dart';
import '../application/planning/estimate_upgrade_impact_use_case.dart';
import '../application/planning/optimize_growth_route_use_case.dart';
import '../application/planning/generate_team_growth_priority_use_case.dart';
import '../domain/account/account_snapshot.dart';
import '../domain/account/account_health_report.dart';
import '../domain/account/snapshot_supplement.dart';
import '../domain/daily_materials/daily_material_models.dart';
import '../domain/history/growth_event.dart';
import '../data/config/ley_line_overflow_repository.dart';
import '../domain/planning/character_farm_plan.dart';
import '../domain/planning/daily_plan.dart';
import '../domain/planning/investment_diagnosis.dart';
import '../domain/planning/ley_line_overflow.dart';
import '../domain/planning/resin_farm_cost_table.dart';
import '../domain/planning/upgrade_option.dart';
import '../domain/planning/growth_route.dart';
import '../domain/planning/growth_route_request.dart';
import '../domain/planning/team_growth_priority.dart';
import '../domain/team/team_models.dart';
import '../data/repositories/drift_growth_goal_repository.dart';
import '../data/repositories/drift_material_inventory_repository.dart';
import '../data/repositories/drift_team_repository.dart';
import '../data/repositories/drift_growth_event_repository.dart';
import '../data/repositories/progress_mutation_repository.dart';
import 'app_providers.dart';
import 'gacha_providers.dart' show gachaCalendarApiProvider;
import 'hoyolab_game_providers.dart' show hoyolabGameDataRepositoryProvider;
import 'hoyolab_providers.dart'
    show featureFlagsProvider, hoyolabSessionProvider;
import 'hoyolab_snapshot_providers.dart' show buildSnapshotSupplement;

/// UTC 現在時刻（テストで差し替え可能）。
final clockProvider = Provider<Clock>((ref) {
  return () => DateTime.now().toUtc();
});

final leyLineOverflowRepositoryProvider =
    Provider<LeyLineOverflowRepository>((ref) {
  return LeyLineOverflowRepository(
    catalogSource: ref.watch(leyLineOverflowCatalogSourceProvider),
    calendarApi: ref.watch(gachaCalendarApiProvider),
    clock: ref.watch(clockProvider),
  );
});

/// 地脈の奔流の開催状態（取得失敗時は非開催）。
final leyLineOverflowStatusProvider =
    FutureProvider<LeyLineOverflowStatus>((ref) async {
  final repo = ref.watch(leyLineOverflowRepositoryProvider);
  return repo.resolveStatus();
});

final growthGoalRepoProvider = FutureProvider((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftGrowthGoalRepository(db);
});
final materialInventoryRepoProvider = FutureProvider((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftMaterialInventoryRepository(db);
});
final teamRepoProvider = FutureProvider((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftTeamRepository(db);
});
final growthEventRepoProvider = FutureProvider((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftGrowthEventRepository(db);
});
final progressMutationRepoProvider = FutureProvider((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftProgressMutationRepository(db);
});

// ── HoYoLAB supplement builder (cache-only, no network) ──────────

Future<AccountSnapshotSupplement> _buildSupplement(Ref ref) async =>
    buildSnapshotSupplement(ref);

/// Batch-fetch owned builds and persist relics into local progress.
/// Failures are swallowed so snapshot/health still load without relics.
Future<void> _ensureHoyolabRelicsPersisted(Ref ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.hoyolabLinkEnabled) return;
  final session = await ref.watch(hoyolabSessionProvider.future);
  if (!session.isLinked) return;

  try {
    final hoyolab = await ref.watch(hoyolabGameDataRepositoryProvider.future);
    final progressRepo = await ref.watch(progressRepositoryProvider.future);
    final userId = await ref.watch(localUserIdProvider.future);
    final builds = await hoyolab.fetchOwnedCharacterBuilds();
    if (builds.isEmpty) return;
    await SyncHoyolabRelicsToProgressUseCase(
      progressRepository: progressRepo,
    )(userId: userId, builds: builds.values);
  } catch (_) {
    // Network / session errors: keep previous local artifacts.
  }
}

// ── AccountSnapshot ───────────────────────────────────────────────

final accountSnapshotProvider = FutureProvider<AccountSnapshot>((ref) async {
  await _ensureHoyolabRelicsPersisted(ref);

  final charRepo = await ref.watch(characterRepositoryProvider.future);
  final progressRepo = await ref.watch(progressRepositoryProvider.future);
  final goalRepo = await ref.watch(growthGoalRepoProvider.future);
  final invRepo = await ref.watch(materialInventoryRepoProvider.future);
  final teamRepo = await ref.watch(teamRepoProvider.future);
  final supplement = await _buildSupplement(ref);
  final userId = await ref.watch(localUserIdProvider.future);

  final useCase = BuildAccountSnapshotUseCase(
    characterRepo: charRepo, progressRepo: progressRepo,
    goalRepo: goalRepo, inventoryRepo: invRepo, teamRepo: teamRepo,
    userId: userId, supplement: supplement,
  );
  return useCase();
});

// ── DailyPlan ─────────────────────────────────────────────────────

final dailyPlanProvider = FutureProvider<DailyPlan>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableDailyPlan) return DailyPlan(userId: '', date: DateTime.now());
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final now = DateTime.now();
  return const GenerateDailyPlanUseCase()(
    userId: snapshot.userId, snapshot: snapshot,
    date: now, weekday: now.weekday, generatedAt: now,
  );
});

// ── Diagnosis (family) ────────────────────────────────────────────

final characterDiagnosisProvider =
    FutureProvider.family<InvestmentDiagnosis, String>((ref, id) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  return const DiagnoseCharacterInvestmentUseCase()(
    snapshot: snapshot, characterId: id, generatedAt: DateTime.now(),
  );
});

// ── Growth Timeline ───────────────────────────────────────────────

final growthTimelineProvider = FutureProvider<List<GrowthEvent>>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableGrowthTimeline) return [];
  final repo = await ref.watch(growthEventRepoProvider.future);
  final userId = await ref.watch(localUserIdProvider.future);
  return repo.getByUser(userId, limit: 50);
});

// ── Health Report ─────────────────────────────────────────────────

final accountHealthReportProvider =
    FutureProvider<AccountHealthReport>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableAccountHealth) return const AccountHealthReport();
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  return const GenerateAccountHealthReportUseCase()(
    snapshot: snapshot, generatedAt: DateTime.now(),
  );
});

// ── Provider invalidate helpers ────────────────────────────────────

void invalidateAfterProgressChange(Ref ref, {String? characterId}) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(dailyPlanProvider);
  if (characterId != null) ref.invalidate(characterDiagnosisProvider(characterId));
  ref.invalidate(accountHealthReportProvider);
}

void invalidateAfterGoalChange(Ref ref, {String? characterId}) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(dailyPlanProvider);
  if (characterId != null) ref.invalidate(characterDiagnosisProvider(characterId));
  ref.invalidate(accountHealthReportProvider);
}

void invalidateAfterInventoryChange(Ref ref) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(dailyPlanProvider);
}

void invalidateAfterTeamChange(Ref ref) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(accountHealthReportProvider);
}

// ═══ Phase 3 Providers ═══════════════════════════════════════════

final upgradeOptionsProvider =
    FutureProvider.family<List<UpgradeOption>, String>((ref, goalId) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final goal = snapshot.activeGoals
      .where((g) => g.id == goalId)
      .firstOrNull;
  if (goal == null) return [];
  final char = snapshot.characters
      .where((c) => c.characterId == goal.characterId)
      .firstOrNull;
  if (char == null) return [];
  final characterRepo =
      await ref.watch(characterRepositoryProvider.future);
  final characterUpgrade = await characterRepo.getUpgrade(goal.characterId);
  final weaponId = goal.targetWeaponId ?? char.equippedWeaponId;
  final weapon = weaponId == null
      ? null
      : await characterRepo.getWeapon(weaponId);
  final weaponUpgrade = weaponId == null
      ? null
      : await characterRepo.getWeaponUpgrade(weaponId);

  ResinFarmCostTable? resinTable;
  Map<String, DailyMaterialSeries> materialIndex = const {};
  Map<String, String> materialCategories = const {};
  try {
    resinTable =
        await ref.watch(resinFarmCostRepositoryProvider).getTable();
    final schedule =
        await ref.watch(dailyMaterialScheduleRepositoryProvider).getSchedule();
    materialIndex = schedule.buildMaterialIndex();
    final materials = await characterRepo.getMaterialsMap();
    materialCategories = {
      for (final e in materials.entries) e.key: e.value.category,
    };
  } catch (_) {
    // 樹脂見積もり失敗時はコストなしで続行
  }

  return GenerateUpgradeOptionsUseCase(
    resinFarmCostTable: resinTable,
    materialIndex: materialIndex,
    materialCategories: materialCategories,
  )(
    goal: goal, character: char,
    materialInventory: snapshot.materialInventory,
    promotes: characterUpgrade?.promotes,
    talents: characterUpgrade?.talents,
    weaponPromotes: weaponUpgrade?.promotes,
    weaponLevelUpItemIds: weaponUpgrade?.levelUpItemIds,
    weaponRarity: weapon?.rarity ?? 5,
    generatedAt: DateTime.now(),
  );
});

final upgradeImpactProvider =
    FutureProvider.family<UpgradeImpact, UpgradeOption>((ref, option) async {
  return const EstimateUpgradeImpactUseCase()(option: option);
});

final growthRouteProvider =
    FutureProvider.family<GrowthRoute, GrowthRouteRequest>((ref, req) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final options = <UpgradeOption>[];
  for (final gid in req.goalIds) {
    final goalOpts = await ref.watch(upgradeOptionsProvider(gid).future);
    options.addAll(goalOpts);
  }
  if (options.isEmpty) {
    return GrowthRoute(userId: snapshot.userId, startDate: req.startDate, endDate: req.startDate);
  }

  // Build weekdayMap from daily material schedule if available.
  Map<String, Set<int>>? weekdayMap;
  if (req.weekdayMap != null) {
    weekdayMap = req.weekdayMap;
  } else {
    try {
      final scheduleRepo = ref.watch(dailyMaterialScheduleRepositoryProvider);
      final schedule = await scheduleRepo.getSchedule();
      final built = <String, Set<int>>{};
      for (final series in schedule.talentSeries.followedBy(schedule.weaponSeries)) {
        final daySet = series.days.toSet();
        for (final matId in series.materialIds) {
          built[matId] = daySet;
        }
      }
      weekdayMap = built;
    } catch (_) {
      weekdayMap = null;
    }
  }

  return const OptimizeGrowthRouteUseCase()(
    userId: snapshot.userId, options: options,
    startDate: req.startDate, startWeekday: req.startWeekday,
    dailyResinBudget: req.dailyResinBudget,
    enforceDailyResinBudget: false,
    weekdayMap: weekdayMap,
  );
});

/// 育成ルート目標に対応するキャラ別ファーミング計画（樹脂詳細）。
final characterFarmPlansProvider =
    FutureProvider.family<List<CharacterFarmPlan>, GrowthRouteRequest>(
        (ref, req) async {
  final options = <UpgradeOption>[];
  for (final gid in req.goalIds) {
    final goalOpts = await ref.watch(upgradeOptionsProvider(gid).future);
    options.addAll(goalOpts);
  }
  if (options.isEmpty) return const [];

  final resinTable =
      await ref.watch(resinFarmCostRepositoryProvider).getTable();
  final schedule =
      await ref.watch(dailyMaterialScheduleRepositoryProvider).getSchedule();
  final materialIndex = schedule.buildMaterialIndex();
  final characterRepo = await ref.watch(characterRepositoryProvider.future);
  final materials = await characterRepo.getMaterialsMap();
  final materialCategories = {
    for (final e in materials.entries) e.key: e.value.category,
  };
  final materialNames = {
    for (final e in materials.entries) e.key: e.value.name,
  };
  // 取得中は非開催扱いで通常計算（誤って開催中にしない）。
  final overflowStatus = ref.watch(leyLineOverflowStatusProvider).valueOrNull ??
      LeyLineOverflowStatus.inactive;
  final nowUtc = ref.watch(clockProvider)();

  final byChar = <String, List<UpgradeOption>>{};
  for (final opt in options) {
    byChar.putIfAbsent(opt.characterId, () => []).add(opt);
  }

  final plans = <CharacterFarmPlan>[
    for (final e in byChar.entries)
      buildCharacterFarmPlan(
        characterId: e.key,
        options: e.value,
        table: resinTable,
        materialIndex: materialIndex,
        materialCategories: materialCategories,
        materialNames: materialNames,
        leyLineOverflowStatus: overflowStatus,
        nowUtc: nowUtc,
      ),
  ];
  plans.sort((a, b) {
    final byResin = b.totalResin.compareTo(a.totalResin);
    if (byResin != 0) return byResin;
    return a.characterId.compareTo(b.characterId);
  });
  // Attach aggregate as last item with sentinel id when multiple characters.
  if (plans.length > 1) {
    final aggregate = mergeCharacterFarmPlans(
      allOptions: options,
      table: resinTable,
      materialIndex: materialIndex,
      materialCategories: materialCategories,
      materialNames: materialNames,
      leyLineOverflowStatus: overflowStatus,
      nowUtc: nowUtc,
    );
    return [...plans, aggregate];
  }
  return plans;
});

final teamGrowthPriorityProvider =
    FutureProvider.family<TeamGrowthPriorityReport, String>((ref, teamId) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final teams = snapshot.savedTeams;
  final team = teams
      .where((t) => t is Team && t.id == teamId)
      .cast<Team>()
      .firstOrNull;
  if (team == null) return TeamGrowthPriorityReport(teamId: teamId);
  final optionsByChar = <String, List<UpgradeOption>>{};
  for (final member in team.members) {
    final goal = snapshot.activeGoals
        .where((g) => g.characterId == member.characterId)
        .firstOrNull;
    if (goal != null) {
      optionsByChar[member.characterId] =
          await ref.watch(upgradeOptionsProvider(goal.id).future);
    }
  }
  return const GenerateTeamGrowthPriorityUseCase()(
    team: team, snapshot: snapshot,
    upgradeOptionsByCharacter: optionsByChar,
  );
});
