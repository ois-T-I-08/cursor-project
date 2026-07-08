import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/hoyolab_slider_sync.dart';

void main() {
  group('hoyolab slider sync', () {
    test('maps three talents by order', () {
      final levels = parseHoyolabTalentLevels(const [
        HoyolabTalentInput(name: '通常攻撃', level: 8),
        HoyolabTalentInput(name: '霜華の輪', level: 9),
        HoyolabTalentInput(name: '神里流・霜滅', level: 10),
      ]);

      expect(levels.$1, 8);
      expect(levels.$2, 9);
      expect(levels.$3, 10);
    });

    test('snaps character and weapon level to marks', () {
      final snapshot = buildHoyolabSliderSnapshot(
        level: 88,
        promoteLevel: 6,
        constellation: 2,
        talents: const [],
        weaponId: '11502',
        weaponName: '霧切の廻光',
        weaponLevel: 87,
        weaponRefinement: 3,
      );

      expect(snapshot.level, 90);
      expect(snapshot.weaponLevel, 90);
      expect(snapshot.constellation, 2);
      expect(snapshot.weaponRefinement, 3);
    });
  });
}
