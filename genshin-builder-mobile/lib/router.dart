import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/bootstrap/initial_sync_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/characters/character_detail_screen.dart';
import 'features/characters/character_list_screen.dart';
import 'features/daily_materials/daily_materials_screen.dart';
import 'features/hoyolab/hoyolab_settings_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/bootstrap',
  routes: [
    GoRoute(
      path: '/bootstrap',
      builder: (context, state) => const InitialSyncScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/characters',
          builder: (context, state) => const CharacterListScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => CharacterDetailScreen(
                characterId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/daily',
          builder: (context, state) => const DailyMaterialsScreen(),
        ),
        GoRoute(
          path: '/bookmarks',
          builder: (context, state) => const BookmarksScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'hoyolab',
              builder: (context, state) => const HoyolabSettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/characters')) return 1;
    if (loc.startsWith('/daily')) return 2;
    if (loc.startsWith('/bookmarks')) return 3;
    if (loc.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/');
            case 1:
              context.go('/characters');
            case 2:
              context.go('/daily');
            case 3:
              context.go('/bookmarks');
            case 4:
              context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'キャラ',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: '曜日',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: '素材',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
