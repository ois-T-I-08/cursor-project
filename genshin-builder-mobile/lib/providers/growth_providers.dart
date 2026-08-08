import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account/build_account_snapshot_use_case.dart';
import '../application/account/generate_health_report_use_case.dart';
import '../application/planning/apply_daily_plan_enrichment.dart';
import '../application/planning/build_deterministic_daily_plan_proposal.dart';
import '../application/planning/daily_plan_fingerprint.dart';
import '../application/planning/generate_daily_plan_use_case.dart';
import '../application/planning/diagnose_investment_use_case.dart';
import '../application/planning/generate_upgrade_options_use_case.dart';
import '../application/planning/estimate_upgrade_impact_use_case.dart';
import '../application/planning/optimize_growth_route_use_case.dart';
import '../application/planning/generate_team_growth_priority_use_case.dart';
import '../data/daily_plan/backend_daily_plan_enrich_api.dart';
import '../data/daily_plan/daily_plan_proposal_store.dart';
import '../domain/account/account_snapshot.dart';
import '../domain/account/account_health_report.dart';
import '../domain/account/snapshot_supplement.dart';
import '../domain/daily_materials/daily_material_models.dart';
import '../domain/history/growth_event.dart';
import '../domain/planning/daily_plan.dart';
import '../domain/planning/daily_plan_item_key.dart';
import '../domain/planning/daily_plan_proposal.dart';
import '../domain/planning/investment_diagnosis.dart';
import '../domain/planning/upgrade_option.dart';
import '../domain/planning/growth_route.dart';
import '../domain/planning/growth_route_request.dart';
import '../domain/planning/team_growth_priority.dart';
import '../domain/planning/resin_farm_estimate.dart';
import '../domain/planning/resin_farm_cost_table.dart';
import '../domain/team/team_models.dart';
import '../data/repositories/drift_growth_goal_repository.dart';
import '../data/repositories/drift_material_inventory_repository.dart';
import '../data/repositories/drift_team_repository.dart';
import '../data/repositories/drift_growth_event_repository.dart';
import '../data/repositories/progress_mutation_repository.dart';
import 'app_providers.dart';
import 'daily_materials_providers.dart';
import 'hoyolab_providers.dart' show featureFlagsProvider;
import 'hoyolab_snapshot_providers.dart' show buildSnapshotSupplement;
import '../application/daily_plan_notifications/daily_plan_user_scope.dart';

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
    characterRepo: charRepo,
    progressRepo: progressRepo,
    goalRepo: goalRepo,
    inventoryRepo: invRepo,
    teamRepo: teamRepo,
    userId: userId,
    supplement: supplement,
  );
  return useCase();
});

// ── DailyPlan ─────────────────────────────────────────────────────

final dailyPlanEnrichApiProvider = Provider<BackendDailyPlanEnrichApi>((ref) {
  const baseUrl = String.fromEnvironment(
    'GENSHIN_BUILDER_API_BASE_URL',
    defaultValue: '',
  );
  final api = BackendDailyPlanEnrichApi(baseUrl: baseUrl);
  ref.onDispose(api.dispose);
  return api;
});

final dailyPlanProposalStoreProvider = FutureProvider<DailyPlanProposalStore>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DailyPlanProposalStore(db);
});

final dailyPlanProvider = FutureProvider<DailyPlan>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableDailyPlan) {
    return DailyPlan(userId: '', date: DateTime.now());
  }
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final now = DateTime.now();
  final gameDate = genshinGameDate(now);
  final weekday = gameDate.weekday;

  DailyMaterialsPlan? materialsPlan;
  try {
    materialsPlan = await ref.watch(dailyMaterialsPlanProvider(weekday).future);
  } catch (_) {
    materialsPlan = null;
  }

  final options = <UpgradeOption>[];
  final goals = [...snapshot.activeGoals]
    ..sort((a, b) => b.priority.compareTo(a.priority));
  for (final goal in goals.take(8)) {
    try {
      options.addAll(await ref.watch(upgradeOptionsProvider(goal.id).future));
    } catch (_) {
      // The existing goal fallback remains available when master data is absent.
    }
  }

  var estimatedOptions = options;
  var weekdayLimitedMaterialIds = <String>{};
  var availableMaterialIdsToday = <String>{};
  int? weekdayRunResinCost;
  int? weeklyBossRunResinCost;
  try {
    final schedule =
        await ref.watch(dailyMaterialScheduleRepositoryProvider).getSchedule();
    final table = await ref.watch(resinFarmCostRepositoryProvider).getTable();
    final materials = await ref.watch(materialsMapProvider.future);
    final materialIndex = schedule.buildMaterialIndex();
    final categories = {
      for (final entry in materials.entries) entry.key: entry.value.category,
    };
    estimatedOptions = [
      for (final option in options)
        option.copyWith(
          estimatedResinCost: estimateResinCostForUpgradeOption(
            option: option,
            table: table,
            materialIndex: materialIndex,
            materialCategories: categories,
          ),
        ),
    ];
    weekdayLimitedMaterialIds = {
      for (final series in schedule.allSeries)
        for (final materialId in series.materialIds) materialId,
    };
    availableMaterialIdsToday = {
      for (final series in schedule.seriesForDay(weekday))
        for (final materialId in series.materialIds) materialId,
    };
    weekdayRunResinCost =
        table.costFor(ResinFarmKind.talentDomain)?.resinPerRun;
    weeklyBossRunResinCost =
        table.costFor(ResinFarmKind.weeklyBoss)?.resinPerRun;
  } catch (_) {
    // Missing optional estimate data must not hide the deterministic plan.
  }

  var bookmarkedCharacterIds = <String>{};
  try {
    final bookmarks = await ref.watch(bookmarkRepositoryProvider.future);
    bookmarkedCharacterIds =
        (await bookmarks.getAll())
            .map((bookmark) => bookmark.characterId)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
  } catch (_) {
    // Bookmark facts are optional.
  }

  return const GenerateDailyPlanUseCase()(
    userId: snapshot.userId,
    snapshot: snapshot,
    date: gameDate,
    weekday: weekday,
    materialsPlan: materialsPlan,
    upgradeOptions: estimatedOptions,
    weekdayLimitedMaterialIds: weekdayLimitedMaterialIds,
    availableMaterialIdsToday: availableMaterialIdsToday,
    bookmarkedCharacterIds: bookmarkedCharacterIds,
    weekdayRunResinCost: weekdayRunResinCost,
    weeklyBossRunResinCost: weeklyBossRunResinCost,
    generatedAt: now,
  );
});

final dailyPlanProposalProvider = FutureProvider.family<DailyPlanProposal, int>(
  (ref, generation) async {
    final plan = await ref.watch(dailyPlanProvider.future);
    if (plan.items.isEmpty) {
      return buildDeterministicDailyPlanProposal(plan);
    }

    try {
      final proposal = await ref
          .watch(dailyPlanEnrichApiProvider)
          .suggest(
            plan: plan,
            weekday: plan.date.weekday,
            clientScope: dailyPlanSafeUserScope(plan.userId),
            proposalFingerprint: dailyPlanFingerprint(plan),
            force: generation > 0,
          );
      return proposal ?? buildDeterministicDailyPlanProposal(plan);
    } catch (_) {
      return buildDeterministicDailyPlanProposal(plan);
    }
  },
);

/// Base plan plus a user-adopted, still-current validated proposal.
final adoptedDailyPlanProvider = FutureProvider<DailyPlan>((ref) async {
  final plan = await ref.watch(dailyPlanProvider.future);
  if (plan.items.isEmpty) return plan;
  final store = await ref.watch(dailyPlanProposalStoreProvider.future);
  final proposal = await store.read(
    userScope: dailyPlanSafeUserScope(plan.userId),
    localDate: formatLocalDate(plan.date),
    planFingerprint: dailyPlanFingerprint(plan),
    plan: plan,
  );
  return proposal == null ? plan : applyDailyPlanProposal(plan, proposal);
});

// ── Diagnosis (family) ────────────────────────────────────────────

final characterDiagnosisProvider =
    FutureProvider.family<InvestmentDiagnosis, String>((ref, id) async {
      final flags = await ref.watch(featureFlagsProvider.future);
      if (!flags.enableInvestmentDiagnosis) {
        return InvestmentDiagnosis(characterId: id);
      }
      final snapshot = await ref.watch(accountSnapshotProvider.future);
      return const DiagnoseCharacterInvestmentUseCase()(
        snapshot: snapshot,
        characterId: id,
        generatedAt: DateTime.now(),
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

final accountHealthReportProvider = FutureProvider<AccountHealthReport>((
  ref,
) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableAccountHealth) return const AccountHealthReport();
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  return const GenerateAccountHealthReportUseCase()(
    snapshot: snapshot,
    generatedAt: DateTime.now(),
  );
});

// ── Provider invalidate helpers ────────────────────────────────────

void invalidateAfterProgressChange(Ref ref, {String? characterId}) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(dailyPlanProvider);
  if (characterId != null) {
    ref.invalidate(characterDiagnosisProvider(characterId));
  }
  ref.invalidate(accountHealthReportProvider);
}

void invalidateAfterGoalChange(Ref ref, {String? characterId}) {
  ref.invalidate(accountSnapshotProvider);
  ref.invalidate(dailyPlanProvider);
  if (characterId != null) {
    ref.invalidate(characterDiagnosisProvider(characterId));
  }
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

final upgradeOptionsProvider = FutureProvider.family<
  List<UpgradeOption>,
  String
>((ref, goalId) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final goal = snapshot.activeGoals.where((g) => g.id == goalId).firstOrNull;
  if (goal == null) return [];
  final char =
      snapshot.characters
          .where((c) => c.characterId == goal.characterId)
          .firstOrNull;
  if (char == null) return [];
  final characterRepo = await ref.watch(characterRepositoryProvider.future);
  final characterUpgrade = await characterRepo.getUpgrade(goal.characterId);
  final weaponId = goal.targetWeaponId ?? char.equippedWeaponId;
  final weapon =
      weaponId == null ? null : await characterRepo.getWeapon(weaponId);
  final weaponUpgrade =
      weaponId == null ? null : await characterRepo.getWeaponUpgrade(weaponId);
  return const GenerateUpgradeOptionsUseCase()(
    goal: goal,
    character: char,
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
        return GrowthRoute(
          userId: snapshot.userId,
          startDate: req.startDate,
          endDate: req.startDate,
        );
      }

      // Build weekdayMap from daily material schedule if available.
      Map<String, Set<int>>? weekdayMap;
      if (req.weekdayMap != null) {
        weekdayMap = req.weekdayMap;
      } else {
        try {
          final scheduleRepo = ref.watch(
            dailyMaterialScheduleRepositoryProvider,
          );
          final schedule = await scheduleRepo.getSchedule();
          final built = <String, Set<int>>{};
          for (final series in schedule.talentSeries.followedBy(
            schedule.weaponSeries,
          )) {
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
        userId: snapshot.userId,
        options: options,
        startDate: req.startDate,
        startWeekday: req.startWeekday,
        dailyResinBudget: req.dailyResinBudget,
        weekdayMap: weekdayMap,
      );
    });

final teamGrowthPriorityProvider = FutureProvider.family<
  TeamGrowthPriorityReport,
  String
>((ref, teamId) async {
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final teams = snapshot.savedTeams;
  final team =
      teams.where((t) => t is Team && t.id == teamId).cast<Team>().firstOrNull;
  if (team == null) return TeamGrowthPriorityReport(teamId: teamId);
  final optionsByChar = <String, List<UpgradeOption>>{};
  for (final member in team.members) {
    final goal =
        snapshot.activeGoals
            .where((g) => g.characterId == member.characterId)
            .firstOrNull;
    if (goal != null) {
      optionsByChar[member.characterId] = await ref.watch(
        upgradeOptionsProvider(goal.id).future,
      );
    }
  }
  return const GenerateTeamGrowthPriorityUseCase()(
    team: team,
    snapshot: snapshot,
    upgradeOptionsByCharacter: optionsByChar,
  );
});
