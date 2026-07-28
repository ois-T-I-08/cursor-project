/// Stable request for [OptimizeGrowthRouteUseCase].
/// Used as a Provider family key — fully immutable.
class GrowthRouteRequest {
  GrowthRouteRequest({
    required List<String> goalIds,
    required this.startDate,
    required this.startWeekday,
    this.dailyResinBudget,
    Map<String, Set<int>>? weekdayMap,
  }) : goalIds = List.unmodifiable(
         List<String>.from(goalIds.toSet())..sort(), // dedupe + sort
       ),
       weekdayMap = _copyWeekdayMap(weekdayMap);

  /// Sorted, deduplicated list of goal IDs (immutable).
  final List<String> goalIds;

  final DateTime startDate;
  final int startWeekday; // 1=Mon..7=Sun
  final int? dailyResinBudget;

  /// materialId → available weekdays (1=Mon..7=Sun).
  /// Deeply immutable — Map and inner Sets cannot be mutated.
  final Map<String, Set<int>>? weekdayMap;

  // ── Deep copy ─────────────────────────────────────────────────────

  static Map<String, Set<int>>? _copyWeekdayMap(Map<String, Set<int>>? source) {
    if (source == null) return null;
    final keys = source.keys.toList()..sort();
    final copied = <String, Set<int>>{};
    for (final key in keys) {
      final days = source[key]!.toList()..sort();
      copied[key] = Set.unmodifiable(days);
    }
    return Map.unmodifiable(copied);
  }

  // ── Equality ─────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrowthRouteRequest &&
          other.startDate == startDate &&
          other.startWeekday == startWeekday &&
          other.dailyResinBudget == dailyResinBudget &&
          _listEquals(other.goalIds, goalIds) &&
          _weekdayMapEquals(other.weekdayMap, weekdayMap);

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _weekdayMapEquals(
    Map<String, Set<int>>? a,
    Map<String, Set<int>>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final otherDays = b[entry.key];
      if (otherDays == null) return false;
      if (!_setEquals(entry.value, otherDays)) return false;
    }
    return true;
  }

  static bool _setEquals(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  // ── HashCode ──────────────────────────────────────────────────────

  @override
  int get hashCode => Object.hash(
    Object.hashAll(goalIds),
    startDate,
    startWeekday,
    dailyResinBudget,
    _weekdayMapHash(weekdayMap),
  );

  static int _weekdayMapHash(Map<String, Set<int>>? map) {
    if (map == null) return 0; // distinct from empty map
    final keys = map.keys.toList()..sort();
    final entryHashes = keys.map((key) {
      final days = map[key]!.toList()..sort();
      return Object.hash(key, Object.hashAll(days));
    });
    return Object.hashAll(entryHashes);
  }
}
