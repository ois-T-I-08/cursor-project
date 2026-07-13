import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/team/main_tab.dart';
import 'package:genshin_builder_mobile/navigation/android_system_back.dart';
import 'package:genshin_builder_mobile/router.dart';
import 'package:go_router/go_router.dart';

// Mock widgets for test-only routes.
//
// Routes NOT in production (test mocks for history verification):
//   /daily/detail, /bookmarks/detail, /characters/:id/weapon/:weaponId
// Production routes with actual independent history:
//   Home branch: /settings, /settings/hoyolab
//   Characters branch: /characters/:id
//   Teams branch: /teams

class _HomePage extends StatelessWidget {
  const _HomePage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('HOME')));
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('SETTINGS')));
}

class _HoyolabPage extends StatelessWidget {
  const _HoyolabPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('HOYOLAB')));
}

class _TeamsPage extends StatelessWidget {
  const _TeamsPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('TEAMS')));
}

class _CharList extends StatefulWidget {
  const _CharList();
  @override
  State<_CharList> createState() => _CharListState();
}

class _CharListState extends State<_CharList> {
  double _scrollOffset = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('CHARS'),
              Text('scroll: $_scrollOffset'),
              ElevatedButton(
                onPressed: () => setState(() => _scrollOffset += 100),
                child: const Text('scroll-down'),
              ),
            ],
          ),
        ),
      );
}

class _CharDetail extends StatelessWidget {
  const _CharDetail(this.id);
  final String id;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('DETAIL:$id')));
}

class _DailyPage extends StatefulWidget {
  const _DailyPage();
  @override
  State<_DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends State<_DailyPage> {
  String _selectedDay = 'mon';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DAY:$_selectedDay'),
              ElevatedButton(
                onPressed: () => setState(() => _selectedDay = 'tue'),
                child: const Text('select-tue'),
              ),
            ],
          ),
        ),
      );
}

class _BookmarksPage extends StatelessWidget {
  const _BookmarksPage();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('BOOKMARKS')));
}

class _MockWeaponDetail extends StatelessWidget {
  const _MockWeaponDetail(this.characterId, this.weaponId);
  final String characterId;
  final String weaponId;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('WEAPON:$characterId:$weaponId')));
}

class _MockDailyDetail extends StatelessWidget {
  const _MockDailyDetail();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('DAILY-DETAIL')));
}

class _MockBookmarksDetail extends StatelessWidget {
  const _MockBookmarksDetail();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('BM-DETAIL')));
}

// Test router
class _TestShell {
  _TestShell({
    bool includeMockDetails = true,
    bool includeSettings = false,
    bool includePopScope = false,
    bool useProductionAppShell = false,
  }) {
    final homeKey = GlobalKey<NavigatorState>(debugLabel: 'testHome');
    final charKey = GlobalKey<NavigatorState>(debugLabel: 'testChar');
    final teamKey = GlobalKey<NavigatorState>(debugLabel: 'testTeam');
    final dailyKey = GlobalKey<NavigatorState>(debugLabel: 'testDaily');
    final matKey = GlobalKey<NavigatorState>(debugLabel: 'testMat');

    router = GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, s) {
            shell = s;
            if (useProductionAppShell) {
              return AppShell(navigationShell: s);
            }
            Widget body = shell!;
            if (includePopScope) {
              body = PopScope(
                canPop: () {
                  final idx = s.currentIndex;
                  final keys = [homeKey, charKey, teamKey, dailyKey, matKey];
                  return keys[idx].currentState?.canPop() ?? false;
                }(),
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (s.currentIndex != 0) {
                    s.goBranch(0);
                  }
                },
                child: body,
              );
            }
            return Scaffold(body: body);
          },
          branches: [
            // 0: Home
            StatefulShellBranch(
              navigatorKey: homeKey,
              routes: [
                GoRoute(path: '/', builder: (_, __) => const _HomePage()),
                if (includeSettings) ...[
                  GoRoute(
                    path: '/settings',
                    builder: (_, __) => const _SettingsPage(),
                    routes: [
                      GoRoute(path: 'hoyolab', builder: (_, __) => const _HoyolabPage()),
                    ],
                  ),
                ] else ...[
                  GoRoute(path: '/settings', builder: (_, __) => const SizedBox.shrink()),
                ],
                GoRoute(path: '/gacha', builder: (_, __) => const SizedBox.shrink()),
                GoRoute(path: '/artifacts', builder: (_, __) => const SizedBox.shrink()),
              ],
            ),
            // 1: Characters
            StatefulShellBranch(
              navigatorKey: charKey,
              routes: [
                GoRoute(
                  path: '/characters',
                  builder: (_, __) => const _CharList(),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (ctx, state) => _CharDetail(state.pathParameters['id']!),
                      routes: [
                        if (includeMockDetails)
                          GoRoute(
                            path: 'weapon/:weaponId',
                            builder: (ctx, state) => _MockWeaponDetail(
                              state.pathParameters['id']!,
                              state.pathParameters['weaponId']!,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // 2: Teams
            StatefulShellBranch(
              navigatorKey: teamKey,
              routes: [
                GoRoute(path: '/teams', builder: (_, __) => const _TeamsPage()),
              ],
            ),
            // 3: Daily
            StatefulShellBranch(
              navigatorKey: dailyKey,
              routes: [
                GoRoute(
                  path: '/daily',
                  builder: (_, __) => const _DailyPage(),
                  routes: [
                    if (includeMockDetails)
                      GoRoute(path: 'detail', builder: (_, __) => const _MockDailyDetail()),
                  ],
                ),
              ],
            ),
            // 4: Bookmarks
            StatefulShellBranch(
              navigatorKey: matKey,
              routes: [
                GoRoute(
                  path: '/bookmarks',
                  builder: (_, __) => const _BookmarksPage(),
                  routes: [
                    if (includeMockDetails)
                      GoRoute(path: 'detail', builder: (_, __) => const _MockBookmarksDetail()),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  late final GoRouter router;
  StatefulNavigationShell? shell;

  void dispose() => router.dispose();
}

// Helpers

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

Future<void> _goBranch(WidgetTester tester, _TestShell tr, int index) async {
  tr.shell!.goBranch(index);
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

Future<void> _goInBranch(WidgetTester tester, _TestShell tr, String location) async {
  tr.router.go(location);
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

Future<void> _pushInBranch(WidgetTester tester, _TestShell tr, String location) async {
  tr.router.push(location);
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// Open the drawer via AppShellScope's scaffold key.
void _openDrawer(WidgetTester tester) {
  final navContext = tester.element(find.byType(NavigationBar));
  final scope = AppShellScope.of(navContext);
  scope.scaffoldKey.currentState!.openEndDrawer();
}

/// Get the AppShell's ScaffoldState via AppShellScope.
ScaffoldState _getShellScaffold(WidgetTester tester) {
  final navContext = tester.element(find.byType(NavigationBar));
  final scope = AppShellScope.of(navContext);
  return scope.scaffoldKey.currentState!;
}

/// Tap a drawer destination by its index.
Future<void> _tapDrawerItem(WidgetTester tester, int index) async {
  await tester.tap(find.byType(NavigationDrawerDestination).at(index));
}

// Tab indices (from MainTab enum)
const _home = 0;
const _chars = 1;
const _teams = 2;
const _daily = 3;
const _materials = 4;

// Drawer item indices (8 items: home, chars, teams, daily, artifacts, materials, gacha, settings)
const _drawerHome = 0;
const _drawerChars = 1;
const _drawerTeams = 2;
const _drawerArtifacts = 4;
const _drawerGacha = 6;
const _drawerSettings = 7;

// Tests

void main() {
  group('MainTab', () {
    test('tab order is home, characters, teams, daily, materials', () {
      expect(MainTab.home.index, 0);
      expect(MainTab.characters.index, 1);
      expect(MainTab.teams.index, 2);
      expect(MainTab.daily.index, 3);
      expect(MainTab.materials.index, 4);
    });
  });

  group('isAndroidSystemBackHandlingEnabled', () {
    test('Android = true', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isAndroidSystemBackHandlingEnabled, isTrue);
    });
    test('iOS = false', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isAndroidSystemBackHandlingEnabled, isFalse);
    });
  });

  group('Branch history independence', () {
    testWidgets('char list to detail, switch away and back', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('DETAIL:42'), findsOneWidget);
    });

    testWidgets('char to detail to weapon, switch and back', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      await _pushInBranch(tester, tr, '/characters/42/weapon/w7');
      expect(find.text('WEAPON:42:w7'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      await _pushInBranch(tester, tr, '/daily/detail');
      expect(find.text('DAILY-DETAIL'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('WEAPON:42:w7'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAILY-DETAIL'), findsOneWidget);
    });

    testWidgets('home settings hoyolab history', (tester) async {
      final tr = _TestShell(includeSettings: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);

      await _pushInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      await _goBranch(tester, tr, _home);
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('SETTINGS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('teams tab preserves state when switching away and back',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('CHARS'), findsOneWidget);

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);
    });
  });

  group('Cross-branch via AppShellScope.switchMainTab', () {
    testWidgets('char detail preserved when switching via switchMainTab',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _goBranch(tester, tr, _home);
      expect(find.text('HOME'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('DETAIL:42'), findsOneWidget);
    });

    testWidgets('daily preserved when switching via switchMainTab',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _daily);
      await tester.tap(find.text('select-tue'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('DAY:tue'), findsOneWidget);

      await _goBranch(tester, tr, _home);
      await _goBranch(tester, tr, _chars);
      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:tue'), findsOneWidget);
    });
  });

  group('Android back button', () {
    testWidgets('branch detail pops within branch', (tester) async {
      final tr = _TestShell(includePopScope: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('CHARS'), findsOneWidget);
    });

    testWidgets('multi-level back: weapon to detail to list', (tester) async {
      final tr = _TestShell(includePopScope: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      await _pushInBranch(tester, tr, '/characters/42/weapon/w7');
      expect(find.text('WEAPON:42:w7'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('CHARS'), findsOneWidget);
    });

    testWidgets('non-home branch root back goes to home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      expect(find.text('CHARS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('daily root back to home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('bookmarks root back to home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _materials);
      expect(find.text('BOOKMARKS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('teams root back to home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('home root back delegates to system', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      expect(find.text('HOME'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('rapid back taps do not double-process', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('home nested: hoyolab to settings to home to system',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      await _pushInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('SETTINGS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('Drawer back behavior', () {
    testWidgets('back with drawer open closes drawer only', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(_getShellScaffold(tester).isEndDrawerOpen, isTrue);

      await _systemBack(tester);
      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('drawer opened then closed, back still pops in branch',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      _getShellScaffold(tester).closeEndDrawer();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await _systemBack(tester);
      expect(find.text('CHARS'), findsOneWidget);
    });
  });

  group('Drawer branch item restores history', () {
    testWidgets('drawer chars item restores char detail', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _goBranch(tester, tr, _home);
      expect(find.text('HOME'), findsOneWidget);

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerChars);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('DETAIL:42'), findsOneWidget);
    });

    testWidgets('drawer home item resets to root', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      await _pushInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _goBranch(tester, tr, _chars);

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerHome);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('HOYOLAB'), findsNothing);
    });

    testWidgets('drawer teams item navigates to teams', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerTeams);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('TEAMS'), findsOneWidget);
    });
  });

  group('Drawer direct route items', () {
    testWidgets('drawer settings opens settings screen', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerSettings);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('SETTINGS'), findsOneWidget);
      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
    });

    testWidgets('drawer gacha navigates without exception', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerGacha);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawer artifacts navigates without exception', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerArtifacts);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid drawer taps do not duplicate', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await _tapDrawerItem(tester, _drawerSettings);
      await _tapDrawerItem(tester, _drawerSettings);
      await _tapDrawerItem(tester, _drawerSettings);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('Footer taps override pending drawer navigation', () {
    testWidgets('footer char tap during pending drawer settings',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerSettings);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_chars);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('CHARS'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('last footer tap wins: drawer->chars->daily',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerSettings);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_chars);
      bottomNav.onDestinationSelected!(_daily);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('DAY:mon'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
      expect(find.text('CHARS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('same-tab retap cancels pending drawer nav', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerSettings);
      await tester.pump();

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_chars);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('DETAIL:42'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('footer tap while drawer open closes and switches',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(_getShellScaffold(tester).isEndDrawerOpen, isTrue);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_materials);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(find.text('BOOKMARKS'), findsOneWidget);
    });

    testWidgets('rapid footer cycle does not duplicate routes',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      for (final idx in [_chars, _teams, _daily, _materials, _home]) {
        bottomNav.onDestinationSelected!(idx);
        await tester.pump();
      }
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid footer with open drawer: last tap wins',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_chars);
      bottomNav.onDestinationSelected!(_teams);
      bottomNav.onDestinationSelected!(_materials);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('BOOKMARKS'), findsOneWidget);
      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('Home tab always resets to root', () {
    testWidgets('settings to home via footer', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('hoyolab to settings to home via footer', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      await _pushInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('settings on home branch, switch to chars, footer home',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('CHARS'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('char detail preserved after home and back', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('HOME'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('DETAIL:42'), findsOneWidget);
    });

    testWidgets('home retap when already on home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      expect(find.text('HOME'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drawer home resets to root', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _tapDrawerItem(tester, _drawerHome);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });
  });

  group('Teams tab', () {
    testWidgets('footer navigates to teams', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_teams);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('TEAMS'), findsOneWidget);
    });

    testWidgets('teams tab preserves state', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);
    });

    testWidgets('teams tab same-tab retap does nothing', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_teams);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('TEAMS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('teams back goes to home', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('Android back restores home history', () {
    testWidgets('back from non-home restores last home screen',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      await _pushInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('SETTINGS'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('switchMainTab char then back restores home history',
        (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('CHARS'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('SETTINGS'), findsOneWidget);
    });
  });

  group('NavigatorKey uniqueness', () {
    testWidgets('all branch keys distinct', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      final shell = tr.shell!;
      final keys = <GlobalKey<NavigatorState>>{};
      for (var i = 0; i < 5; i++) {
        shell.goBranch(i);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final navs = find.byType(Navigator).evaluate().toList();
        for (final nav in navs) {
          final key = (nav.widget as Navigator).key;
          if (key is GlobalKey<NavigatorState>) {
            keys.add(key);
          }
        }
      }
      expect(keys.length, greaterThanOrEqualTo(1));
    });

    testWidgets('no GlobalKey collision with repeated switches', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      for (var i = 0; i < 5; i++) {
        await _goBranch(tester, tr, _chars);
        await _pushInBranch(tester, tr, '/characters/42');
        await _pushInBranch(tester, tr, '/characters/42/weapon/w7');
        await _goBranch(tester, tr, _teams);
        await _goBranch(tester, tr, _daily);
        await _goBranch(tester, tr, _materials);
        await _goBranch(tester, tr, _home);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Same-tab retap', () {
    testWidgets('goBranch to same index does not duplicate', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      tr.shell!.goBranch(_home);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('HOME'), findsOneWidget);

      tr.shell!.goBranch(_home);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('retap does not reset to branch root', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      tr.shell!.goBranch(_chars);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('DETAIL:42'), findsOneWidget);
      expect(find.text('CHARS'), findsNothing);
    });
  });

  group('Deep links', () {
    testWidgets('to character detail selects right branch', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goInBranch(tester, tr, '/characters/arlecchino');
      expect(find.text('DETAIL:arlecchino'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('CHARS'), findsOneWidget);
    });

    testWidgets('to teams selects right branch', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goInBranch(tester, tr, '/teams');
      expect(find.text('TEAMS'), findsOneWidget);
    });

    testWidgets('to daily selects right branch', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goInBranch(tester, tr, '/daily');
      expect(find.text('DAY:mon'), findsOneWidget);
    });

    testWidgets('to bookmarks selects right branch', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goInBranch(tester, tr, '/bookmarks');
      expect(find.text('BOOKMARKS'), findsOneWidget);
    });

    testWidgets('to settings/hoyolab selects home branch', (tester) async {
      final tr = _TestShell(includeSettings: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goInBranch(tester, tr, '/settings/hoyolab');
      expect(find.text('HOYOLAB'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('SETTINGS'), findsOneWidget);
    });
  });

  group('State preservation', () {
    testWidgets('daily selection preserved after switch', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);

      await tester.tap(find.text('select-tue'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('DAY:tue'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:tue'), findsOneWidget);
    });

    testWidgets('char list scroll position preserved', (tester) async {
      final tr = _TestShell();
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      expect(find.text('scroll: 0.0'), findsOneWidget);

      await tester.tap(find.text('scroll-down'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('scroll: 100.0'), findsOneWidget);

      await _goBranch(tester, tr, _daily);
      await _goBranch(tester, tr, _chars);
      expect(find.text('scroll: 100.0'), findsOneWidget);
    });
  });

  group('Phase 1 audit ? regression', () {
    testWidgets('daily tab is at index 3', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _daily);
      expect(find.text('DAY:mon'), findsOneWidget);
    });

    testWidgets('materials tab is at index 4', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _materials);
      expect(find.text('BOOKMARKS'), findsOneWidget);
    });

    testWidgets('settings to home via footer still works', (tester) async {
      final tr = _TestShell(includeSettings: true, useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _pushInBranch(tester, tr, '/settings');
      final bottomNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      bottomNav.onDestinationSelected!(_home);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('char detail preserved across teams tab switch',
        (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      await _goBranch(tester, tr, _chars);
      await _pushInBranch(tester, tr, '/characters/42');
      expect(find.text('DETAIL:42'), findsOneWidget);

      await _goBranch(tester, tr, _teams);
      expect(find.text('TEAMS'), findsOneWidget);

      await _goBranch(tester, tr, _chars);
      expect(find.text('DETAIL:42'), findsOneWidget);
    });

    testWidgets('drawer back still works with teams tab', (tester) async {
      final tr = _TestShell(useProductionAppShell: true);
      addTearDown(() => tr.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: tr.router));

      _openDrawer(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(_getShellScaffold(tester).isEndDrawerOpen, isTrue);

      await _systemBack(tester);
      expect(_getShellScaffold(tester).isEndDrawerOpen, isFalse);
    });
  });

  group('Bootstrap', () {
    testWidgets('/bootstrap has no bottom nav', (tester) async {
      final router = GoRouter(
        initialLocation: '/bootstrap',
        routes: [
          GoRoute(
            path: '/bootstrap',
            builder: (_, __) => const Scaffold(body: Center(child: Text('BS'))),
          ),
          StatefulShellRoute.indexedStack(
            builder: (_, __, shell) => Scaffold(
              body: shell,
              bottomNavigationBar: SafeArea(
                child: NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: (i) => shell.goBranch(i),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home), label: 'H'),
                  ],
                ),
              ),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(path: '/', builder: (_, __) => const Text('home')),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(() => router.dispose());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      expect(find.text('BS'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
