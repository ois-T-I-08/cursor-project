import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/hoyolab/complete_hoyolab_web_login_use_case.dart';
import '../config/feature_flags.dart';
import '../data/hoyolab/hoyolab_cookie_service.dart';
import '../data/hoyolab/models/daily_note.dart';
import '../data/repositories/hoyolab_repository.dart';
import '../data/secure/secure_storage_service.dart';
import 'app_providers.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final hoyolabCookieServiceProvider = Provider<HoyolabCookieService>((ref) {
  return const HoyolabCookieService();
});

final featureFlagsProvider = FutureProvider<FeatureFlags>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rawHoyolab = await db.getSetting(FeatureFlags.hoyolabLinkEnabledKey);
  final hoyolab =
      rawHoyolab == null
          ? FeatureFlags.defaultHoyolabLinkEnabled
          : rawHoyolab == 'true';

  final rawGoals = await db.getSetting(FeatureFlags.growthGoalsEnabledKey);
  final goals =
      rawGoals == null
          ? FeatureFlags.defaultGrowthGoalsEnabled
          : rawGoals == 'true';

  final rawInventory = await db.getSetting(
    FeatureFlags.materialInventoryEnabledKey,
  );
  final inventory =
      rawInventory == null
          ? FeatureFlags.defaultMaterialInventoryEnabled
          : rawInventory == 'true';

  final rawTeams = await db.getSetting(FeatureFlags.savedTeamsEnabledKey);
  final teams =
      rawTeams == null
          ? FeatureFlags.defaultSavedTeamsEnabled
          : rawTeams == 'true';

  final rawDailyPlan = await db.getSetting(FeatureFlags.dailyPlanEnabledKey);
  final dailyPlan =
      rawDailyPlan == null
          ? FeatureFlags.defaultDailyPlanEnabled
          : rawDailyPlan == 'true';

  final rawDiag = await db.getSetting(
    FeatureFlags.investmentDiagnosisEnabledKey,
  );
  final diag =
      rawDiag == null
          ? FeatureFlags.defaultInvestmentDiagnosisEnabled
          : rawDiag == 'true';

  final rawTimeline = await db.getSetting(
    FeatureFlags.growthTimelineEnabledKey,
  );
  final timeline =
      rawTimeline == null
          ? FeatureFlags.defaultGrowthTimelineEnabled
          : rawTimeline == 'true';

  final rawHealth = await db.getSetting(FeatureFlags.accountHealthEnabledKey);
  final health =
      rawHealth == null
          ? FeatureFlags.defaultAccountHealthEnabled
          : rawHealth == 'true';

  return FeatureFlags(
    hoyolabLinkEnabled: hoyolab,
    enableGrowthGoals: goals,
    enableMaterialInventory: inventory,
    enableSavedTeams: teams,
    enableDailyPlan: dailyPlan,
    enableInvestmentDiagnosis: diag,
    enableGrowthTimeline: timeline,
    enableAccountHealth: health,
  );
});

final hoyolabRepositoryProvider = FutureProvider<HoyolabRepository>((
  ref,
) async {
  final secure = ref.watch(secureStorageProvider);
  final flags = await ref.watch(featureFlagsProvider.future);
  return HoyolabRepository(
    secureStorage: secure,
    featureFlags: flags,
    cookieService: ref.watch(hoyolabCookieServiceProvider),
  );
});

final completeHoyolabWebLoginUseCaseProvider =
    FutureProvider<CompleteHoyolabWebLoginUseCase>((ref) async {
      final repo = await ref.watch(hoyolabRepositoryProvider.future);
      return CompleteHoyolabWebLoginUseCase(
        cookieService: ref.watch(hoyolabCookieServiceProvider),
        repository: repo,
      );
    });

final hoyolabSessionProvider = FutureProvider<HoyolabSession>((ref) async {
  final flags = await ref.watch(featureFlagsProvider.future);
  if (!flags.hoyolabLinkEnabled) {
    return HoyolabSession.unlinked;
  }
  final repo = await ref.watch(hoyolabRepositoryProvider.future);
  return repo.loadSession();
});

final hoyolabRolesProvider = FutureProvider<List<HoyolabGameRole>>((ref) async {
  final session = await ref.watch(hoyolabSessionProvider.future);
  if (!session.isLinked) return [];
  final repo = await ref.watch(hoyolabRepositoryProvider.future);
  return repo.fetchAvailableRoles();
});
