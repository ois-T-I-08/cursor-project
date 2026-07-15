import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account/build_account_snapshot_use_case.dart';
import '../application/account/generate_health_report_use_case.dart';
import '../application/planning/generate_daily_plan_use_case.dart';
import '../application/planning/diagnose_investment_use_case.dart';
import '../application/planning/generate_upgrade_options_use_case.dart';
import '../application/planning/estimate_upgrade_impact_use_case.dart';
import '../application/planning/optimize_growth_route_use_case.dart';
import '../application/planning/generate_team_growth_priority_use_case.dart';
import '../domain/account/account_snapshot.dart';
import '../domain/account/account_health_report.dart';
import '../domain/account/snapshot_supplement.dart';
import '../domain/history/growth_event.dart';
import '../domain/planning/daily_plan.dart';
import '../domain/planning/investment_diagnosis.dart';
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
import 'hoyolab_providers.dart' show featureFlagsProvider;
import 'hoyolab_snapshot_providers.dart' show buildSnapshotSupplement;

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

// ── AccountSnapshot ───────────────────────────────────────────────

final accountSnapshotProvider = FutureProvider<AccountSnapshot>((ref) async {
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
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableInvestmentDiagnosis) return InvestmentDiagnosis(characterId: id);
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
  return const GenerateUpgradeOptionsUseCase()(
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
    weekdayMap: weekdayMap,
  );
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
