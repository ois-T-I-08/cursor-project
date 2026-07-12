import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'application/hoyolab_reminders/notification_bootstrap.dart';
import 'application/hoyolab_reminders/notification_tap_router.dart';
import 'data/artifact_score/artifact_score_type_override_loader.dart';
import 'router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureArtifactScoreTypeOverrideLoader();
  // P1-8B: do not block runApp; permission is not requested here.
  unawaited(NotificationBootstrap.ensureInitialized());
  NotificationTapRouter.attachRouter(appRouter);
  runApp(const ProviderScope(child: GenshinBuilderApp()));
}
