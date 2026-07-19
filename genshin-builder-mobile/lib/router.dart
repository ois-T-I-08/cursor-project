import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain/team/main_tab.dart';
import 'features/abyss/abyss_statistics_screen.dart';
import 'features/artifacts/artifact_sets_screen.dart';
import 'features/bootstrap/initial_sync_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/characters/character_detail_screen.dart';
import 'features/characters/character_list_screen.dart';
import 'features/daily_materials/daily_materials_screen.dart';
import 'features/gacha/gacha_screen.dart';
import 'features/home/home_screen.dart';
import 'features/hoyolab/hoyolab_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/teams/team_builder_screen.dart';
import 'features/growth/daily_plan_screen.dart';
import 'features/growth/growth_timeline_screen.dart';
import 'features/growth/account_health_screen.dart';
import 'features/growth/growth_route_screen.dart';
import 'features/growth/team_growth_priority_screen.dart';
import 'domain/planning/growth_route_request.dart';
import 'navigation/android_system_back.dart';

// ---------------------------------------------------------------------------
// Navigator Keys (all distinct instances)
// ---------------------------------------------------------------------------

/// Root Navigator for /bootstrap etc.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Home branch Navigator.
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'homeBranch');

/// Characters branch Navigator.
final _charactersNavKey = GlobalKey<NavigatorState>(
  debugLabel: 'charactersBranch',
);

/// Teams branch Navigator.
final _teamsNavKey = GlobalKey<NavigatorState>(debugLabel: 'teamsBranch');

/// Daily branch Navigator.
final _dailyNavKey = GlobalKey<NavigatorState>(debugLabel: 'dailyBranch');

/// Materials branch Navigator.
final _materialsNavKey = GlobalKey<NavigatorState>(
  debugLabel: 'materialsBranch',
);

// ---------------------------------------------------------------------------
// GoRouter
// ---------------------------------------------------------------------------

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/bootstrap',
  routes: [
    GoRoute(
      path: '/bootstrap',
      builder: (context, state) => const InitialSyncScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder:
          (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
      branches: [
        // 0: Home
        StatefulShellBranch(
          navigatorKey: _homeNavKey,
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/abyss',
              builder: (context, state) => const AbyssStatisticsScreen(),
            ),
            GoRoute(
              path: '/artifacts',
              builder: (context, state) => const ArtifactSetsScreen(),
            ),
            GoRoute(
              path: '/gacha',
              builder: (context, state) => const GachaScreen(),
            ),
            GoRoute(
              path: '/daily-plan',
              builder: (context, state) => const DailyPlanScreen(),
            ),
            GoRoute(
              path: '/growth-timeline',
              builder: (context, state) => const GrowthTimelineScreen(),
            ),
            GoRoute(
              path: '/account-health',
              builder: (context, state) => const AccountHealthScreen(),
            ),
            GoRoute(
              path: '/growth-route',
              builder: (context, state) {
                final request =
                    state.extra is GrowthRouteRequest
                        ? state.extra as GrowthRouteRequest
                        : null;
                return GrowthRouteScreen(request: request);
              },
            ),
            GoRoute(
              path: '/team-priority',
              builder: (context, state) {
                final teamId =
                    state.extra is String ? state.extra as String : null;
                return TeamGrowthPriorityScreen(teamId: teamId);
              },
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
        // 1: Characters
        StatefulShellBranch(
          navigatorKey: _charactersNavKey,
          routes: [
            GoRoute(
              path: '/characters',
              builder: (context, state) => const CharacterListScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder:
                      (context, state) => CharacterDetailScreen(
                        characterId: state.pathParameters['id']!,
                      ),
                ),
              ],
            ),
          ],
        ),
        // 2: Teams
        StatefulShellBranch(
          navigatorKey: _teamsNavKey,
          routes: [
            GoRoute(
              path: '/teams',
              builder: (context, state) => const TeamBuilderScreen(),
            ),
          ],
        ),
        // 3: Daily
        StatefulShellBranch(
          navigatorKey: _dailyNavKey,
          routes: [
            GoRoute(
              path: '/daily',
              builder: (context, state) => const DailyMaterialsScreen(),
            ),
          ],
        ),
        // 4: Bookmarks
        StatefulShellBranch(
          navigatorKey: _materialsNavKey,
          routes: [
            GoRoute(
              path: '/bookmarks',
              builder: (context, state) => const BookmarksScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Branch NavigatorKey array (index order).
final _branchNavKeys = [
  _homeNavKey,
  _charactersNavKey,
  _teamsNavKey,
  _dailyNavKey,
  _materialsNavKey,
];

// ---------------------------------------------------------------------------
// DrawerDestination
// ---------------------------------------------------------------------------

class _DrawerDestination {
  const _DrawerDestination._({
    required this.label,
    required this.icon,
    this.branchIndex,
    this.path,
  });

  /// Main tab switch (uses goBranch).
  const _DrawerDestination.branch({
    required String label,
    required IconData icon,
    required int branchIndex,
  }) : this._(label: label, icon: icon, branchIndex: branchIndex, path: null);

  /// Same-branch route navigation (uses router.go).
  const _DrawerDestination.route({
    required String label,
    required IconData icon,
    required String path,
    required int branchIndex,
  }) : this._(label: label, icon: icon, branchIndex: branchIndex, path: path);

  final String label;
  final IconData icon;
  final int? branchIndex;
  final String? path;

  /// Whether this is a main tab switch (no same-branch route navigation needed).
  bool get isMainTabSwitch => path == null;
}

// ---------------------------------------------------------------------------
// NavItem (bottom nav)
// ---------------------------------------------------------------------------

class _NavItem {
  const _NavItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final MainTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  int get branchIndex => tab.index;
}

final _bottomNavItems = <_NavItem>[
  const _NavItem(
    tab: MainTab.home,
    label: '\u30db\u30fc\u30e0',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  const _NavItem(
    tab: MainTab.characters,
    label: '\u30ad\u30e3\u30e9',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
  ),
  const _NavItem(
    tab: MainTab.teams,
    label: '\u7de8\u6210',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  const _NavItem(
    tab: MainTab.daily,
    label: '\u66dc\u65e5',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today,
  ),
  const _NavItem(
    tab: MainTab.materials,
    label: '\u7d20\u6750',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
  ),
];

final _drawerDestinations = <_DrawerDestination>[
  _DrawerDestination.branch(
    label: '\u30db\u30fc\u30e0',
    icon: Icons.home_outlined,
    branchIndex: MainTab.home.index,
  ),
  _DrawerDestination.branch(
    label: '\u30ad\u30e3\u30e9',
    icon: Icons.people_outlined,
    branchIndex: MainTab.characters.index,
  ),
  _DrawerDestination.branch(
    label: '\u7de8\u6210',
    icon: Icons.groups_outlined,
    branchIndex: MainTab.teams.index,
  ),
  _DrawerDestination.branch(
    label: '\u66dc\u65e5',
    icon: Icons.calendar_today_outlined,
    branchIndex: MainTab.daily.index,
  ),
  _DrawerDestination.route(
    label: '\u8056\u907a\u7269',
    icon: Icons.diamond_outlined,
    path: '/artifacts',
    branchIndex: MainTab.home.index,
  ),
  _DrawerDestination.branch(
    label: '\u7d20\u6750',
    icon: Icons.bookmark_outline,
    branchIndex: MainTab.materials.index,
  ),
  _DrawerDestination.route(
    label: '\u6df1\u5883\u87ba\u65cb\u7d71\u8a08',
    icon: Icons.auto_graph_outlined,
    path: '/abyss',
    branchIndex: MainTab.home.index,
  ),
  _DrawerDestination.route(
    label: '\u30ac\u30c1\u30e3',
    icon: Icons.casino_outlined,
    path: '/gacha',
    branchIndex: MainTab.home.index,
  ),
  _DrawerDestination.route(
    label: '\u8a2d\u5b9a',
    icon: Icons.settings_outlined,
    path: '/settings',
    branchIndex: MainTab.home.index,
  ),
];

/// Compute the selected index in the drawer (first matching destination).
int _drawerSelectedIndex(String currentPath) {
  for (var i = 0; i < _drawerDestinations.length; i++) {
    final d = _drawerDestinations[i];
    if (d.path != null && currentPath.startsWith(d.path!)) return i;
    if (d.isMainTabSwitch) {
      if ((d.branchIndex == MainTab.home.index && currentPath == '/') ||
          (d.branchIndex == MainTab.characters.index &&
              currentPath.startsWith('/characters')) ||
          (d.branchIndex == MainTab.teams.index &&
              currentPath.startsWith('/teams')) ||
          (d.branchIndex == MainTab.daily.index &&
              currentPath.startsWith('/daily')) ||
          (d.branchIndex == MainTab.materials.index &&
              currentPath.startsWith('/bookmarks'))) {
        return i;
      }
    }
  }
  return 0;
}

// ---------------------------------------------------------------------------
// AppShellScope
// ---------------------------------------------------------------------------

/// Exposes shell-level operations to descendant widgets.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.switchMainTab,
    required this.currentTabIndex,
    required this.scaffoldKey,
    required super.child,
  });

  /// Switch to the main tab at [index] (use [MainTab.index]).
  /// Same-tab re-taps are a no-op.
  final void Function(int index) switchMainTab;

  /// Currently selected tab index.
  final int currentTabIndex;

  /// Scaffold key for opening the end drawer.
  final GlobalKey<ScaffoldState> scaffoldKey;

  /// Convenience accessor. Throws if scope is missing.
  static AppShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppShellScope>();
    assert(
      scope != null,
      'AppShellScope.of() called with no AppShellScope in context',
    );
    return scope!;
  }

  /// Open the end drawer (backward-compatible static method).
  static AppShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>();

  static void openEndDrawer(BuildContext context) {
    maybeOf(context)?.scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) {
    return currentTabIndex != oldWidget.currentTabIndex ||
        switchMainTab != oldWidget.switchMainTab ||
        scaffoldKey != oldWidget.scaffoldKey;
  }
}

// ---------------------------------------------------------------------------
// AppShell
// ---------------------------------------------------------------------------

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  /// StatefulNavigationShell provided by StatefulShellRoute.indexedStack.
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isEndDrawerOpen = false;
  VoidCallback? _pendingDrawerNavigation;

  /// Check whether the current branch navigator can pop.
  bool get _branchCanPop {
    final key = _branchNavKeys[widget.navigationShell.currentIndex];
    return key.currentState?.canPop() ?? false;
  }

  /// Common footer tab switching logic.
  /// Home always resets to the initial route `/`.
  /// Other tabs preserve their existing navigation history.
  void _switchToTab(int index) {
    // Cancel any pending drawer-triggered navigation.
    _pendingDrawerNavigation = null;

    // Close the drawer immediately if it is open.
    if (_isEndDrawerOpen) {
      _scaffoldKey.currentState?.closeEndDrawer();
    }

    if (index == MainTab.home.index) {
      // Home tab always goes to root, regardless of current branch state.
      widget.navigationShell.goBranch(
        MainTab.home.index,
        initialLocation: true,
      );
      return;
    }

    // Same-tab retap is a no-op (preserves detail screens, scroll, etc.).
    if (index == widget.navigationShell.currentIndex) return;

    widget.navigationShell.goBranch(index);
  }

  /// Tap handler for bottom navigation bar.
  void _onBottomNavTapped(int index) {
    _switchToTab(index);
  }

  /// Schedule a navigation action to execute after the drawer closes.
  void _afterDrawerCloses(VoidCallback action) {
    _pendingDrawerNavigation = action;
    _scaffoldKey.currentState?.closeEndDrawer();
  }

  /// Tap handler for drawer destinations.
  void _onDrawerDestinationSelected(int index) {
    final destination = _drawerDestinations[index];
    final shell = widget.navigationShell;

    if (destination.isMainTabSwitch) {
      if (destination.branchIndex == MainTab.home.index) {
        // Home drawer item: always go to root.
        shell.goBranch(MainTab.home.index, initialLocation: true);
      } else if (destination.branchIndex != shell.currentIndex) {
        // Non-Home branches: preserve history.
        shell.goBranch(destination.branchIndex!);
      }
      _scaffoldKey.currentState?.closeEndDrawer();
    } else {
      // Same-branch direct navigation: switch branch first, then navigate
      // to the specific route after drawer is confirmed closed.
      if (destination.branchIndex != shell.currentIndex) {
        shell.goBranch(destination.branchIndex!);
      }
      _afterDrawerCloses(() {
        if (mounted) {
          GoRouter.of(context).go(destination.path!);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    final currentPath = GoRouterState.of(context).uri.path;
    final theme = Theme.of(context);

    // Compute PopScope conditions with state-tracked drawer.
    final canPop =
        !_isEndDrawerOpen &&
        (_branchCanPop || shell.currentIndex == MainTab.home.index);

    Widget body = shell;

    if (isAndroidSystemBackHandlingEnabled) {
      body = PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;

          // 1. Drawer is open - close it only (no pop, no branch switch).
          if (_isEndDrawerOpen) {
            _scaffoldKey.currentState?.closeEndDrawer();
            return;
          }

          // 2. Non-home tab with no history - switch to home.
          if (shell.currentIndex != MainTab.home.index) {
            shell.goBranch(MainTab.home.index);
            return;
          }

          // 3. Home tab root - delegate to system.
        },
        child: shell,
      );
    }

    final scaffold = Scaffold(
      key: _scaffoldKey,
      endDrawerEnableOpenDragGesture: true,
      onEndDrawerChanged: (isOpen) {
        if (_isEndDrawerOpen == isOpen) return;
        setState(() => _isEndDrawerOpen = isOpen);

        if (!isOpen) {
          final action = _pendingDrawerNavigation;
          _pendingDrawerNavigation = null;
          action?.call();
        }
      },
      endDrawer: NavigationDrawer(
        selectedIndex: _drawerSelectedIndex(currentPath),
        onDestinationSelected: _onDrawerDestinationSelected,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
            child: Text(
              '\u30e1\u30cb\u30e5\u30fc',
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final dest in _drawerDestinations)
            NavigationDrawerDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.icon),
              label: Text(dest.label),
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _onBottomNavTapped,
          destinations: [
            for (final item in _bottomNavItems)
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
          ],
        ),
      ),
    );

    return AppShellScope(
      switchMainTab: _switchToTab,
      currentTabIndex: shell.currentIndex,
      scaffoldKey: _scaffoldKey,
      child: scaffold,
    );
  }
}
