import 'growth_route.dart';
import 'planning_display_labels.dart';

/// 1 キャラ分の樹脂内訳（育成ルート全体）。
class CharacterResinBreakdown {
  const CharacterResinBreakdown({
    required this.characterId,
    required this.totalResin,
    required this.lines,
  });

  /// null はキャラ未紐づけアクション。
  final String? characterId;
  final int totalResin;
  final List<CharacterResinLine> lines;
}

/// オプション種別ごとの樹脂小計。
class CharacterResinLine {
  const CharacterResinLine({
    required this.optionType,
    required this.resin,
    required this.actionCount,
  });

  final String optionType;
  final int resin;
  final int actionCount;

  String get label => growthOptionTypeLabel(optionType);
}

/// ルート上の全アクションをキャラ → 種別で集計する。
List<CharacterResinBreakdown> buildCharacterResinBreakdowns(GrowthRoute route) {
  // characterId -> optionType -> (resin, count)
  final byChar = <String?, Map<String, ({int resin, int count})>>{};

  for (final day in route.days) {
    for (final action in day.actions) {
      final type = action.reasons.isNotEmpty
          ? action.reasons.first
          : growthOptionTypeFromOptionId(action.optionId) ?? action.optionId;
      final resin = action.estimatedResinCost ?? 0;
      final charMap = byChar.putIfAbsent(action.characterId, () => {});
      final prev = charMap[type];
      if (prev == null) {
        charMap[type] = (resin: resin, count: 1);
      } else {
        charMap[type] = (resin: prev.resin + resin, count: prev.count + 1);
      }
    }
  }

  final result = <CharacterResinBreakdown>[];
  for (final entry in byChar.entries) {
    final lines = entry.value.entries
        .map(
          (e) => CharacterResinLine(
            optionType: e.key,
            resin: e.value.resin,
            actionCount: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byResin = b.resin.compareTo(a.resin);
        if (byResin != 0) return byResin;
        return a.optionType.compareTo(b.optionType);
      });
    final total = lines.fold<int>(0, (s, l) => s + l.resin);
    result.add(
      CharacterResinBreakdown(
        characterId: entry.key,
        totalResin: total,
        lines: lines,
      ),
    );
  }

  result.sort((a, b) {
    final byResin = b.totalResin.compareTo(a.totalResin);
    if (byResin != 0) return byResin;
    return (a.characterId ?? '').compareTo(b.characterId ?? '');
  });
  return result;
}
