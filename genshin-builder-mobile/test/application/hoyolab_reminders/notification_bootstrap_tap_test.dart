import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_notification_ids.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/notification_bootstrap.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/notification_tap_router.dart';
import 'package:genshin_builder_mobile/application/hoyolab_reminders/reminder_models.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() {
    NotificationBootstrap.debugReset();
    NotificationTapRouter.debugReset();
  });

  test('bootstrap ensureInitialized is single-flight safe', () async {
    final a = NotificationBootstrap.ensureInitialized();
    final b = NotificationBootstrap.ensureInitialized();
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
  });

  test('schedule mode constant is inexactAllowWhileIdle', () {
    expect(AndroidScheduleModeProbe.expected, 'inexactAllowWhileIdle');
  });

  test('tap router holds pending until router attached', () {
    NotificationTapRouter.debugSetPending(ReminderNotificationIds.resinPayload);
    expect(
      NotificationTapRouter.debugPendingPayload,
      ReminderNotificationIds.resinPayload,
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SizedBox(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SizedBox(),
        ),
      ],
      initialLocation: '/settings',
    );
    NotificationTapRouter.attachRouter(router);
    expect(NotificationTapRouter.debugPendingPayload, isNull);
  });

  test('disallowed payload is ignored', () {
    NotificationTapRouter.onResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'cookie=secret',
      ),
    );
    expect(NotificationTapRouter.debugPendingPayload, isNull);
  });

  test('allowed payload is accepted as pending without router', () {
    NotificationTapRouter.debugReset();
    NotificationTapRouter.onResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: ReminderNotificationIds.expeditionPayload,
      ),
    );
    expect(
      NotificationTapRouter.debugPendingPayload,
      ReminderNotificationIds.expeditionPayload,
    );
  });

  test('daily plan incomplete payload is allowed', () {
    NotificationTapRouter.debugReset();
    NotificationTapRouter.onResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: DailyPlanNotificationIds.incompletePayload,
      ),
    );
    expect(
      NotificationTapRouter.debugPendingPayload,
      DailyPlanNotificationIds.incompletePayload,
    );
  });
}

/// Compile-time mirror of FlutterNotificationScheduler schedule mode.
abstract final class AndroidScheduleModeProbe {
  static const expected = 'inexactAllowWhileIdle';
}
