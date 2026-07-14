import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account/build_account_snapshot_use_case.dart';
import '../application/account/generate_health_report_use_case.dart';
import '../application/planning/generate_daily_plan_use_case.dart';
import '../application/planning/diagnose_investment_use_case.dart';
import '../application/history/detect_growth_events_use_case.dart';
import '../domain/account/account_snapshot.dart';
import '../domain/account/account_health_report.dart';
import '../domain/history/growth_event.dart';
import '../domain/models/master_models.dart';
import '../domain/planning/daily_plan.dart';
import '../domain/planning/investment_diagnosis.dart';
import '../domain/recommendation/recommendation.dart';
import '../data/repositories/drift_growth_event_repository.dart';
import 'app_providers.dart';
import 'hoyolab_providers.dart' show featureFlagsProvider;

// ── AccountSnapshot ─────────────────────────────────────────────────

final accountSnapshotProvider = FutureProvider<AccountSnapshot>((ref) async {
  final charRepo = await ref.watch(characterRepositoryProvider.future);
  final progressRepo = await ref.watch(progressRepositoryProvider.future);
  final goalRepo = await ref.watch(growthGoalRepositoryProvider.future);
  final invRepo = await ref.watch(materialInventoryRepositoryProvider.future);
  final teamRepo = await ref.watch(teamRepositoryProvider.future);

  final useCase = BuildAccountSnapshotUseCase(
    characterRepo: charRepo,
    progressRepo: progressRepo,
    goalRepo: goalRepo,
    inventoryRepo: invRepo,
    teamRepo: teamRepo,
    userId: 'local',
  );
  return useCase();
});

// ── DailyPlan ───────────────────────────────────────────────────────

final dailyPlanProvider = FutureProvider<DailyPlan>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableDailyPlan) return DailyPlan(userId: '', date: DateTime.now());

  final snapshot = await ref.watch(accountSnapshotProvider.future);
  final now = DateTime.now();
  return const GenerateDailyPlanUseCase()(
    userId: snapshot.userId,
    snapshot: snapshot,
    date: now,
    weekday: now.weekday,
    generatedAt: now,
  );
});

// ── Investment Diagnosis (family provider per character) ────────────

final characterDiagnosisProvider =
    FutureProvider.family<InvestmentDiagnosis, String>((ref, characterId) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableInvestmentDiagnosis) {
    return InvestmentDiagnosis(characterId: characterId);
  }
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  return const DiagnoseCharacterInvestmentUseCase()(
    snapshot: snapshot,
    characterId: characterId,
    generatedAt: DateTime.now(),
  );
});

// ── Growth Timeline ─────────────────────────────────────────────────

final growthTimelineProvider = FutureProvider<List<GrowthEvent>>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableGrowthTimeline) return [];
  final repo = await ref.watch(growthEventRepositoryProvider.future);
  return repo.getByUser('local', limit: 50);
});

/// Save growth events from a before/after snapshot comparison.
Future<void> saveGrowthEvents({
  required WidgetRef ref,
  required List<CharacterSnapshot> before,
  required List<CharacterSnapshot> after,
  String source = 'localManual',
  bool isInitialSync = false,
}) async {
  final repo = await ref.read(growthEventRepositoryProvider.future);
  final events = const DetectGrowthEventsUseCase()(
    before: before,
    after: after,
    userId: 'local',
    source: source,
    isInitialSync: isInitialSync,
    observedAt: DateTime.now(),
  );
  if (events.isNotEmpty) {
    await repo.saveAll(events);
    ref.invalidate(growthTimelineProvider);
  }
}

// ── Account Health Report ───────────────────────────────────────────

final accountHealthReportProvider =
    FutureProvider<AccountHealthReport>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.enableAccountHealth) {
    return const AccountHealthReport();
  }
  final snapshot = await ref.watch(accountSnapshotProvider.future);
  return const GenerateAccountHealthReportUseCase()(
    snapshot: snapshot,
    generatedAt: DateTime.now(),
  );
});

// ── Repository providers ────────────────────────────────────────────

final growthGoalRepositoryProvider =
    FutureProvider((ref) async => /* already wired in app_providers */ null);

final materialInventoryRepositoryProvider =
    FutureProvider((ref) async => /* already wired */ null);

final teamRepositoryProvider =
    FutureProvider((ref) async => /* already wired */ null);

final growthEventRepositoryProvider =
    FutureProvider((ref) async => /* already wired */ null);
