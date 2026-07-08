import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/material_requirements.dart';
import 'package:genshin_builder_mobile/domain/models/bookmark.dart';
import 'package:genshin_builder_mobile/domain/models/calculation_models.dart';
import 'package:genshin_builder_mobile/domain/talent_progression.dart';

void main() {
  group('getRangeTalentRequirements', () {
    final upgrades = [
      const TalentLevelUpgrade(
        level: 2,
        costItems: {'200001': 3},
        coinCost: 12500,
      ),
      const TalentLevelUpgrade(
        level: 3,
        costItems: {'200001': 6},
        coinCost: 17500,
      ),
    ];

    test('includes iconUrl when resolveIcon provided', () {
      final lines = getRangeTalentRequirements(
        1,
        2,
        10,
        const [
          TalentLevelUpgrade(
            level: 2,
            costItems: {'200001': 3},
            coinCost: 12500,
          ),
        ],
        resolveIcon: (id) => id == '200001' ? 'https://example.com/icon.png' : null,
      );

      final mat = lines.firstWhere((l) => l.materialId == '200001');
      expect(mat.iconUrl, 'https://example.com/icon.png');
    });

    test('sums talent materials and mora', () {
      final lines = getRangeTalentRequirements(1, 3, 10, upgrades);
      expect(lines.length, 2);
      final mat = lines.firstWhere((l) => l.materialId == '200001');
      expect(mat.count, 9);
      expect(lines.any((l) => l.materialId == moraMaterialId), isTrue);
    });
  });

  group('mergeRequirementLines', () {
    test('merges same materialId', () {
      final merged = mergeRequirementLines([
        const RequirementLine(materialId: 'a', name: 'A', count: 1),
        const RequirementLine(materialId: 'a', name: 'A', count: 2),
      ]);
      expect(merged.length, 1);
      expect(merged.first.count, 3);
    });
  });

  group('snapTalentLevel', () {
    test('snaps to integer marks', () {
      expect(snapTalentLevel(4), 4);
      expect(snapTalentLevel(10), 10);
    });
  });
}
