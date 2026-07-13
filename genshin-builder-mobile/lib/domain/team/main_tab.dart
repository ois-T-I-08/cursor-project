/// Main bottom navigation tabs.
///
/// Adding a new tab requires:
/// 1. Insert the new value in this enum at the desired position.
/// 2. Add the corresponding `StatefulShellBranch` in `lib/router.dart`.
/// 3. Add a `_NavItem` entry in `_bottomNavItems`.
/// 4. Add a `_DrawerDestination` entry in `_drawerDestinations`.
/// 5. Add a `GlobalKey<NavigatorState>` and register it in `_branchNavKeys`.
enum MainTab {
  home,
  characters,
  teams,
  daily,
  materials,
}
