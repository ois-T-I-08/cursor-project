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
import 'features/hoyolab/hoyolab_settings_screen.dart';
import 'features/more/more_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/teams/team_builder_screen.dart';
import 'features/growth/daily_plan_screen.dart';
import 'features/growth/growth_hub_screen.dart';
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

/// Today branch Navigator.
final _todayNavKey = GlobalKey<NavigatorState>(debugLabel: 'todayBranch');

/// Characters branch Navigator.
final _charactersNavKey = GlobalKey<NavigatorState>(
  debugLabel: 'charactersBranch',
);

/// Growth branch Navigator.
final _growthNavKey = GlobalKey<NavigatorState>(debugLabel: 'growthBranch');

/// Teams branch Navigator.
final _teamsNavKey = GlobalKey<NavigatorState>(debugLabel: 'teamsBranch');

/// More branch Navigator.
final _moreNavKey = GlobalKey<NavigatorState>(debugLabel: 'moreBranch');

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
        // 0: Today
        StatefulShellBranch(
          navigatorKey: _todayNavKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DailyPlanScreen(),
            ),
            GoRoute(
              path: '/daily-plan',
              builder: (context, state) => const DailyPlanScreen(),
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
        // 2: Growth
        StatefulShellBranch(
          navigatorKey: _growthNavKey,
          routes: [
            GoRoute(
              path: '/growth',
              builder: (context, state) => const GrowthHubScreen(),
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
              path: '/artifacts',
              builder: (context, state) => const ArtifactSetsScreen(),
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
          ],
        ),
        // 3: Teams
        StatefulShellBranch(
          navigatorKey: _teamsNavKey,
          routes: [
            GoRoute(
              path: '/teams',
              builder: (context, state) => const TeamBuilderScreen(),
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
              path: '/abyss',
              builder: (context, state) => const AbyssStatisticsScreen(),
            ),
          ],
        ),
        // 4: More
        StatefulShellBranch(
          navigatorKey: _moreNavKey,
          routes: [
            GoRoute(
              path: '/more',
              builder: (context, state) => const MoreScreen(),
            ),
            GoRoute(
              path: '/gacha',
              builder: (context, state) => const GachaScreen(),
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
    ),
  ],
);

/// Branch NavigatorKey array (index order).
final _branchNavKeys = [
  _todayNavKey,
  _charactersNavKey,
  _growthNavKey,
  _teamsNavKey,
  _moreNavKey,
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
    tab: MainTab.today,
    label: '今日',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
  ),
  const _NavItem(
    tab: MainTab.characters,
    label: '\u30ad\u30e3\u30e9',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
  ),
  const _NavItem(
    tab: MainTab.growth,
    label: '育成',
    icon: Icons.trending_up_outlined,
    selectedIcon: Icons.trending_up,
  ),
  const _NavItem(
    tab: MainTab.teams,
    label: '編成',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  const _NavItem(
    tab: MainTab.more,
    label: 'その他',
    icon: Icons.apps_outlined,
    selectedIcon: Icons.apps,
  ),
];

final _drawerDestinations = <_DrawerDestination>[
  _DrawerDestination.branch(
    label: '今日',
    icon: Icons.today_outlined,
    branchIndex: MainTab.today.index,
  ),
  _DrawerDestination.branch(
    label: '\u30ad\u30e3\u30e9',
    icon: Icons.people_outlined,
    branchIndex: MainTab.characters.index,
  ),
  _DrawerDestination.branch(
    label: '育成',
    icon: Icons.trending_up_outlined,
    branchIndex: MainTab.growth.index,
  ),
  _DrawerDestination.branch(
    label: '編成',
    icon: Icons.groups_outlined,
    branchIndex: MainTab.teams.index,
  ),
  _DrawerDestination.route(
    label: '\u8056\u907a\u7269',
    icon: Icons.diamond_outlined,
    path: '/artifacts',
    branchIndex: MainTab.growth.index,
  ),
  _DrawerDestination.branch(
    label: 'その他',
    icon: Icons.apps_outlined,
    branchIndex: MainTab.more.index,
  ),
  _DrawerDestination.route(
    label: '\u6df1\u5883\u87ba\u65cb\u7d71\u8a08',
    icon: Icons.auto_graph_outlined,
    path: '/abyss',
    branchIndex: MainTab.teams.index,
  ),
  _DrawerDestination.route(
    label: '\u30ac\u30c1\u30e3',
    icon: Icons.casino_outlined,
    path: '/gacha',
    branchIndex: MainTab.more.index,
  ),
  _DrawerDestination.route(
    label: '\u8a2d\u5b9a',
    icon: Icons.settings_outlined,
    path: '/settings',
    branchIndex: MainTab.more.index,
  ),
];

/// Compute the selected index in the drawer (first matching destination).
int _drawerSelectedIndex(String currentPath) {
  for (var i = 0; i < _drawerDestinations.length; i++) {
    final d = _drawerDestinations[i];
    if (d.path != null && currentPath.startsWith(d.path!)) return i;
    if (d.isMainTabSwitch) {
      if ((d.branchIndex == MainTab.today.index &&
              (currentPath == '/' || currentPath == '/daily-plan')) ||
          (d.branchIndex == MainTab.characters.index &&
              currentPath.startsWith('/characters')) ||
          (d.branchIndex == MainTab.growth.index &&
              (currentPath.startsWith('/growth') ||
                  currentPath.startsWith('/daily') ||
                  currentPath.startsWith('/bookmarks') ||
                  currentPath.startsWith('/artifacts'))) ||
          (d.branchIndex == MainTab.teams.index &&
              (currentPath.startsWith('/teams') ||
                  currentPath.startsWith('/team-priority') ||
                  currentPath.startsWith('/abyss'))) ||
          (d.branchIndex == MainTab.more.index &&
              (currentPath.startsWith('/more') ||
                  currentPath.startsWith('/gacha') ||
                  currentPath.startsWith('/settings')))) {
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
  /// Today always resets to the initial route `/`.
  /// Other tabs preserve their existing navigation history.
  void _switchToTab(int index) {
    // Cancel any pending drawer-triggered navigation.
    _pendingDrawerNavigation = null;

    // Close the drawer immediately if it is open.
    if (_isEndDrawerOpen) {
      _scaffoldKey.currentState?.closeEndDrawer();
    }

    if (index == MainTab.today.index) {
      // Today tab always goes to root, regardless of current branch state.
      widget.navigationShell.goBranch(
        MainTab.today.index,
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
      if (destination.branchIndex == MainTab.today.index) {
        // Today drawer item: always go to root.
        shell.goBranch(MainTab.today.index, initialLocation: true);
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
        (_branchCanPop || shell.currentIndex == MainTab.today.index);

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

          // 2. Non-today tab with no history - switch to Today.
          if (shell.currentIndex != MainTab.today.index) {
            shell.goBranch(MainTab.today.index);
            return;
          }

          // 3. Today tab root - delegate to system.
        },
        child: shell,
      );
    }

    final scaffold = Scaffold(
      key: _scaffoldKey,
      // Normal UI enters secondary tools through the visible "その他" tab.
      // The legacy drawer remains only for old deep-link/back compatibility.
      endDrawerEnableOpenDragGesture: false,
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
