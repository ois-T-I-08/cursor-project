import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:genshin_builder_mobile/domain/planning/growth_route_request.dart';
import 'package:genshin_builder_mobile/features/growth/growth_route_screen.dart';
import 'package:genshin_builder_mobile/features/growth/team_growth_priority_screen.dart';

void main() {
  group('GrowthRouteScreen', () {
    testWidgets('renders without extra (empty state)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: GrowthRouteScreen(),
          ),
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('TeamGrowthPriorityScreen', () {
    testWidgets('renders without extra (empty state)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TeamGrowthPriorityScreen(),
          ),
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('Router integration', () {
    testWidgets('growth-route route navigates and renders', (tester) async {
      final router = GoRouter(
        initialLocation: '/growth-route',
        routes: [
          GoRoute(
            path: '/growth-route',
            builder: (ctx, state) => const GrowthRouteScreen(),
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('team-priority route navigates and renders', (tester) async {
      final router = GoRouter(
        initialLocation: '/team-priority',
        routes: [
          GoRoute(
            path: '/team-priority',
            builder: (ctx, state) => const TeamGrowthPriorityScreen(),
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('GrowthRouteRequest equality', () {
    test('same goalIds different order are equal', () {
      final r1 = GrowthRouteRequest(
        goalIds: ['b', 'a'], startDate: DateTime(2026), startWeekday: 1);
      final r2 = GrowthRouteRequest(
        goalIds: ['a', 'b'], startDate: DateTime(2026), startWeekday: 1);
      expect(r1, r2);
      expect(r1.hashCode, r2.hashCode);
    });
  });
}
