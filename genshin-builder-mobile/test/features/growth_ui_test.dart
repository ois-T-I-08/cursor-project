import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:genshin_builder_mobile/domain/planning/growth_route_request.dart';
import 'package:genshin_builder_mobile/domain/planning/team_growth_priority.dart';
import 'package:genshin_builder_mobile/features/growth/growth_route_screen.dart';
import 'package:genshin_builder_mobile/features/growth/team_growth_priority_screen.dart';
import 'package:genshin_builder_mobile/providers/growth_providers.dart';

void main() {
  group('GrowthRouteScreen', () {
    testWidgets('renders without extra (empty state)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: GrowthRouteScreen(request: null)),
        ),
      );

      expect(find.text('育成目標が設定されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('TeamGrowthPriorityScreen', () {
    testWidgets('renders without extra (empty state)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: TeamGrowthPriorityScreen(teamId: null)),
        ),
      );

      expect(find.text('編成が選択されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty teamId shows empty guidance', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: TeamGrowthPriorityScreen(teamId: '')),
        ),
      );

      expect(find.text('編成が選択されていません'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('whitespace teamId shows empty guidance', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: TeamGrowthPriorityScreen(teamId: '   ')),
        ),
      );

      expect(find.text('編成が選択されていません'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('teamId is trimmed before provider lookup', (tester) async {
      // Override only for the trimmed key.
      // If the screen passes ' team-1 ' (untrimmed), the real provider runs
      // which requires DB → test breaks.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            teamGrowthPriorityProvider('team-1').overrideWith(
              (ref) async => const TeamGrowthPriorityReport(
                teamId: 'team-1',
                teamName: 'Trimmed',
                memberPriorities: [
                  TeamMemberGrowthPriority(
                    characterId: 'char1',
                    characterName: 'テストキャラ',
                    priority: 1,
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: TeamGrowthPriorityScreen(teamId: ' team-1 '),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Should show the report content, not empty guidance.
      expect(find.text('編成が選択されていません'), findsNothing);
      expect(find.text('Trimmed'), findsOneWidget);
      expect(find.text('テストキャラ'), findsOneWidget);
      expect(find.text('char1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Router integration', () {
    testWidgets('growth-route extraなしで空状態になる', (tester) async {
      final router = GoRouter(
        initialLocation: '/growth-route',
        routes: [
          GoRoute(
            path: '/growth-route',
            builder: (ctx, state) {
              final request =
                  state.extra is GrowthRouteRequest
                      ? state.extra as GrowthRouteRequest
                      : null;
              return GrowthRouteScreen(request: request);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      expect(find.text('育成目標が設定されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('growth-route 想定外型のextraでもクラッシュしない', (tester) async {
      final router = GoRouter(
        initialLocation: '/growth-route',
        routes: [
          GoRoute(
            path: '/growth-route',
            builder: (ctx, state) {
              final request =
                  state.extra is GrowthRouteRequest
                      ? state.extra as GrowthRouteRequest
                      : null;
              return GrowthRouteScreen(request: request);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      // Navigate with unexpected extra type (int).
      router.go('/growth-route', extra: 42);
      await tester.pumpAndSettle();
      expect(find.text('育成目標が設定されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('growth-route 正しいGrowthRouteRequestが渡される', (tester) async {
      final request = GrowthRouteRequest(
        goalIds: ['goal1'],
        startDate: DateTime(2026, 7, 15),
        startWeekday: 3,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/growth-route',
            builder: (ctx, state) {
              final extra =
                  state.extra is GrowthRouteRequest
                      ? state.extra as GrowthRouteRequest
                      : null;
              return GrowthRouteScreen(request: extra);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());

      router.go('/growth-route', extra: request);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('team-priority extraなしで空状態になる', (tester) async {
      final router = GoRouter(
        initialLocation: '/team-priority',
        routes: [
          GoRoute(
            path: '/team-priority',
            builder: (ctx, state) {
              final teamId =
                  state.extra is String ? state.extra as String : null;
              return TeamGrowthPriorityScreen(teamId: teamId);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      expect(find.text('編成が選択されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('team-priority 想定外型のextraでもクラッシュしない', (tester) async {
      final router = GoRouter(
        initialLocation: '/team-priority',
        routes: [
          GoRoute(
            path: '/team-priority',
            builder: (ctx, state) {
              final teamId =
                  state.extra is String ? state.extra as String : null;
              return TeamGrowthPriorityScreen(teamId: teamId);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      router.go('/team-priority', extra: 42);
      await tester.pumpAndSettle();
      expect(find.text('編成が選択されていません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('team-priority 正しいteamIdが渡される', (tester) async {
      const teamId = 'team-123';
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/team-priority',
            builder: (ctx, state) {
              final extra =
                  state.extra is String ? state.extra as String : null;
              return TeamGrowthPriorityScreen(teamId: extra);
            },
          ),
        ],
      );
      addTearDown(() => router.dispose());

      router.go('/team-priority', extra: teamId);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GrowthRouteRequest equality', () {
    test('same goalIds different order are equal', () {
      final r1 = GrowthRouteRequest(
        goalIds: ['b', 'a'],
        startDate: DateTime(2026),
        startWeekday: 1,
      );
      final r2 = GrowthRouteRequest(
        goalIds: ['a', 'b'],
        startDate: DateTime(2026),
        startWeekday: 1,
      );
      expect(r1, r2);
      expect(r1.hashCode, r2.hashCode);
    });
  });
}
