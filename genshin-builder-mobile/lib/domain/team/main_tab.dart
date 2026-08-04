/// User-goal based bottom navigation tabs.
///
/// The deprecated aliases keep older call sites and notification-era tests
/// source compatible while navigation migrates to the new information
/// architecture.
enum MainTab {
  today,
  characters,
  growth,
  teams,
  more;

  @Deprecated('Use MainTab.today')
  static const home = today;

  @Deprecated('Use MainTab.growth')
  static const daily = growth;

  @Deprecated('Use MainTab.more')
  static const materials = more;
}
