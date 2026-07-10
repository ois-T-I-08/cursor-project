import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_material_models.dart';
import 'package:genshin_builder_mobile/domain/daily_materials/daily_progress_prefetch.dart';
import 'package:genshin_builder_mobile/domain/models/calculation_models.dart';

void main() {
  test('characterIdsNeedingTalentMaterialsOnDay filters by weekday series', () {
    final schedule = DailyMaterialSchedule.fromJson({
      'version': 1,
      'talentSeries': [
        {
          'id': 'light',
          'name': '天光',
          'region': '稲妻',
          'days': [3, 6],
          'materialIds': ['104326', '104327', '104328'],
        },
        {
          'id': 'freedom',
          'name': '自由',
          'region': 'モンド',
          'days': [1, 4],
          'materialIds': ['104301', '104302', '104303'],
        },
      ],
      'weaponSeries': <Map<String, dynamic>>[],
    });

    final talents = {
      'raiden': {
        'skill_0': [
          const TalentLevelUpgrade(
            level: 2,
            coinCost: 0,
            costItems: {'104328': 3},
          ),
        ],
      },
      'jean': {
        'skill_0': [
          const TalentLevelUpgrade(
            level: 2,
            coinCost: 0,
            costItems: {'104301': 3},
          ),
        ],
      },
    };

    final wed = characterIdsNeedingTalentMaterialsOnDay(
      schedule: schedule,
      weekday: DateTime.wednesday,
      talentsByCharacterId: talents,
    );
    expect(wed, {'raiden'});

    final mon = characterIdsNeedingTalentMaterialsOnDay(
      schedule: schedule,
      weekday: DateTime.monday,
      talentsByCharacterId: talents,
    );
    expect(mon, {'jean'});

    final sun = characterIdsNeedingTalentMaterialsOnDay(
      schedule: schedule,
      weekday: DateTime.sunday,
      talentsByCharacterId: talents,
    );
    expect(sun, {'raiden', 'jean'});
  });
}
