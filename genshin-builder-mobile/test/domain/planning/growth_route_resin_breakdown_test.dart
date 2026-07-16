import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_route.dart';
import 'package:genshin_builder_mobile/domain/planning/growth_route_resin_breakdown.dart';

void main() {
  group('buildCharacterResinBreakdowns', () {
    test('aggregates resin by character and option type', () {
      final route = GrowthRoute(
        userId: 'u',
        startDate: DateTime(2026, 7, 14),
        endDate: DateTime(2026, 7, 15),
        days: [
          GrowthRouteDay(
            date: DateTime(2026, 7, 14),
            weekday: 1,
            actions: const [
              GrowthRouteAction(
                optionId: 'g1_level',
                actionType: 'generalMaterial',
                characterId: 'c1',
                estimatedResinCost: 40,
                reasons: ['level'],
              ),
              GrowthRouteAction(
                optionId: 'g1_talentNormal',
                actionType: 'weekdayMaterial',
                characterId: 'c1',
                estimatedResinCost: 60,
                reasons: ['talentNormal'],
              ),
            ],
          ),
          GrowthRouteDay(
            date: DateTime(2026, 7, 15),
            weekday: 2,
            actions: const [
              GrowthRouteAction(
                optionId: 'g2_weapon',
                actionType: 'weekdayMaterial',
                characterId: 'c2',
                estimatedResinCost: 20,
                reasons: ['weapon'],
              ),
            ],
          ),
        ],
      );

      final list = buildCharacterResinBreakdowns(route);
      expect(list.length, 2);
      expect(list.first.characterId, 'c1');
      expect(list.first.totalResin, 100);
      expect(list.first.lines.map((l) => l.optionType).toList(), [
        'talentNormal',
        'level',
      ]);
      expect(list.last.characterId, 'c2');
      expect(list.last.totalResin, 20);
    });

    test('empty route yields empty breakdown', () {
      final route = GrowthRoute(
        userId: 'u',
        startDate: DateTime(2026, 7, 14),
        endDate: DateTime(2026, 7, 14),
      );
      expect(buildCharacterResinBreakdowns(route), isEmpty);
    });
  });
}
