import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account/build_account_snapshot_use_case.dart';
import '../application/account/generate_health_report_use_case.dart';
import '../application/planning/generate_daily_plan_use_case.dart';
import '../application/planning/diagnose_investment_use_case.dart';
import '../domain/account/account_snapshot.dart';
import '../domain/account/account_health_report.dart';
import '../domain/account/snapshot_supplement.dart';
import '../domain/history/growth_event.dart';
import '../domain/planning/daily_plan.dart';
import '../domain/planning/investment_diagnosis.dart';
import '../data/repositories/drift_growth_goal_repository.dart';
import '../data/repositories/drift_material_inventory_repository.dart';
import '../data/repositories/drift_team_repository.dart';
import '../data/repositories/drift_growth_event_repository.dart';
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

  final useCase = BuildAccountSnapshotUseCase(
    characterRepo: charRepo, progressRepo: progressRepo,
    goalRepo: goalRepo, inventoryRepo: invRepo, teamRepo: teamRepo,
    userId: 'local', supplement: supplement,
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
  return repo.getByUser('local', limit: 50);
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
