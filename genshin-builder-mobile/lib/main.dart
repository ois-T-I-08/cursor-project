import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'application/daily_plan_notifications/daily_plan_incomplete_worker.dart';
import 'application/hoyolab_reminders/notification_bootstrap.dart';
import 'application/hoyolab_reminders/notification_tap_router.dart';
import 'data/artifact_score/artifact_score_type_override_loader.dart';
import 'router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureArtifactScoreTypeOverrideLoader();
  // P1-8B: do not block runApp; permission is not requested here.
  unawaited(NotificationBootstrap.ensureInitialized());
  // P1-8C: WorkManager callback registration (no permission prompt).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(
      Workmanager().initialize(dailyPlanIncompleteCallbackDispatcher),
    );
  }
  NotificationTapRouter.attachRouter(appRouter);
  runApp(const ProviderScope(child: GenshinBuilderApp()));
}
