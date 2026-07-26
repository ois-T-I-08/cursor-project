import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/daily_plan_notifications/daily_plan_notification_coordinator.dart';
import 'providers/app_providers.dart';
import 'providers/daily_plan_notification_providers.dart';
import 'router.dart';

class GenshinBuilderApp extends ConsumerStatefulWidget {
  const GenshinBuilderApp({super.key});

  @override
  ConsumerState<GenshinBuilderApp> createState() => _GenshinBuilderAppState();
}

class _GenshinBuilderAppState extends ConsumerState<GenshinBuilderApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDailyPlanSchedule());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureDailyPlanSchedule();
    }
  }

  void _ensureDailyPlanSchedule() {
    // ignore: discarded_futures
    () async {
      try {
        final userId = await ref.read(localUserIdProvider.future);
        final coordinator =
            await ref.read(dailyPlanNotificationCoordinatorProvider.future);
        ensureDailyPlanIncompleteScheduledUnawaited(coordinator, userId);
      } catch (_) {
        // Non-fatal: schedule is best-effort on start/resume.
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Genshin Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6FA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
