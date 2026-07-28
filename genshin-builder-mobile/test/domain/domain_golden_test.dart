import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';
import 'package:genshin_builder_mobile/domain/bookmark_utils.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';
import 'package:genshin_builder_mobile/domain/level_progression.dart';
import 'package:genshin_builder_mobile/domain/material_requirements.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';
import 'package:genshin_builder_mobile/domain/models/bookmark.dart';
import 'package:genshin_builder_mobile/domain/models/calculation_models.dart';
import 'package:genshin_builder_mobile/domain/talent_progression.dart';
import 'package:genshin_builder_mobile/domain/weapon_exp.dart';

/// shared/domain-golden/cases.json を読み、Dart ドメイン実装とパリティ検証する。
void main() {
  final golden = _loadGolden();

  test('loads golden file', () {
    expect(golden['version'], 1);
    expect((golden['suites'] as Map).isNotEmpty, isTrue);
  });

  final suites = golden['suites'] as Map<String, dynamic>;

  group('clampInt', () {
    for (final c in _cases(suites, 'clampInt')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(
          clampInt(input['value'], input['min'] as int, input['max'] as int),
          c['expected'],
        );
      });
    }
  });

  group('snapToLevelMark', () {
    for (final c in _cases(suites, 'snapToLevelMark')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(snapToLevelMark(input['value']), c['expected']);
      });
    }
  });

  group('getWeaponExpBetweenMarks', () {
    for (final c in _cases(suites, 'getWeaponExpBetweenMarks')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(
          getWeaponExpBetweenMarks(
            input['from'] as int,
            input['to'] as int,
            input['rarity'] as int,
          ),
          c['expected'],
        );
      });
    }
  });

  group('bookmarkKeys', () {
    const character = BookmarkCharacterSource(
      characterId: 'hu-tao',
      characterName: '胡桃',
      characterIconUrl: 'https://example.com/hu-tao.png',
    );

    for (final c in _cases(suites, 'bookmarkKeys')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        final fn = c['fn'] as String?;

        if (fn == 'makeBookmarkId') {
          expect(
            makeBookmarkId(
              input['sourceKey'] as String,
              input['materialId'] as String,
            ),
            c['expected'],
          );
          return;
        }

        final ctx = CultivationBookmarkContext(
          kind: _parseKind(input['kind'] as String),
          targetId: input['targetId'] as String,
          targetName: input['targetName'] as String,
          subLabel: input['subLabel'] as String?,
          character: character,
        );

        if (fn == 'makeRangeSourceKey') {
          expect(
            makeRangeSourceKey(ctx, input['from'] as int, input['to'] as int),
            c['expected'],
          );
          return;
        }

        if (fn == 'makeItemSourceKey') {
          expect(
            makeItemSourceKey(
              ctx,
              input['scope'] as String,
              input['materialId'] as String,
            ),
            c['expected'],
          );
          return;
        }

        fail('Unknown bookmarkKeys fn: $fn');
      });
    }
  });

  group('getNextStageRequirements', () {
    for (final c in _cases(suites, 'getNextStageRequirements')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        final promotes =
            (input['promotes'] as List)
                .map((p) => _parsePromote(p as Map<String, dynamic>))
                .toList();
        final stage = getNextStageRequirements(
          input['currentLevel'] as int,
          promotes,
          input['kind'] as String,
          input['weaponRarity'] as int,
        );
        expect(stage, isNotNull);
        final expected = c['expected'] as Map<String, dynamic>;
        expect(stage!.fromLevel, expected['fromLevel']);
        expect(stage.toLevel, expected['toLevel']);
        expect(stage.expTotal, expected['expTotal']);
        expect(stage.mora, expected['mora']);

        final materialsById = <String, int>{
          for (final m in stage.materials) m.materialId: m.count,
        };
        expect(
          materialsById,
          Map<String, int>.from(expected['materialsById'] as Map),
        );
        expect(
          stage.levelUpMaterials.map((m) => m.materialId).toList(),
          List<String>.from(expected['levelUpMaterialIds'] as List),
        );
      });
    }
  });

  group('getRangeLevelRequirements', () {
    for (final c in _cases(suites, 'getRangeLevelRequirements')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        final promotes =
            (input['promotes'] as List)
                .map((p) => _parsePromote(p as Map<String, dynamic>))
                .toList();
        final lines = getRangeLevelRequirements(
          input['fromLevel'] as int,
          input['toLevel'] as int,
          promotes,
          input['kind'] as String,
        );
        final expected = c['expected'] as Map<String, dynamic>;
        final expectedMap =
            expected['linesByMaterialId'] as Map<String, dynamic>;
        final actual = <String, Map<String, Object?>>{};
        for (final line in lines) {
          actual[line.materialId] = {
            'count': line.count,
            if (line.isMora) 'isMora': true else 'isMora': false,
          };
        }
        final normalizedExpected = <String, Map<String, Object?>>{};
        for (final entry in expectedMap.entries) {
          final v = Map<String, Object?>.from(entry.value as Map);
          normalizedExpected[entry.key] = {
            'count': v['count'],
            'isMora': v['isMora'] ?? false,
          };
        }
        expect(actual, normalizedExpected);
      });
    }
  });

  group('getRangeTalentRequirements', () {
    for (final c in _cases(suites, 'getRangeTalentRequirements')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        final upgrades =
            (input['upgrades'] as List)
                .map((u) => _parseTalentUpgrade(u as Map<String, dynamic>))
                .toList();
        final lines = getRangeTalentRequirements(
          input['fromLevel'] as int,
          input['toLevel'] as int,
          input['maxLevel'] as int,
          upgrades,
        );
        final expected = c['expected'] as Map<String, dynamic>;
        final expectedMap =
            expected['linesByMaterialId'] as Map<String, dynamic>;
        final actual = <String, Map<String, Object?>>{};
        for (final line in lines) {
          actual[line.materialId] = {'count': line.count};
        }
        final normalizedExpected = <String, Map<String, Object?>>{};
        for (final entry in expectedMap.entries) {
          final v = Map<String, Object?>.from(entry.value as Map);
          normalizedExpected[entry.key] = {'count': v['count']};
        }
        expect(actual, normalizedExpected);
      });
    }
  });

  group('snapTalentLevel', () {
    for (final c in _cases(suites, 'snapTalentLevel')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(
          snapTalentLevel(input['value'], input['max'] as int),
          c['expected'],
        );
      });
    }
  });

  group('artifactMainStatValue', () {
    for (final c in _cases(suites, 'artifactMainStatValue')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(
          artifactMainStatValue(
            input['statName'] as String,
            input['level'] as int,
          ),
          c['expected'],
        );
      });
    }
  });

  group('inferScoreType', () {
    for (final c in _cases(suites, 'inferScoreType')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        expect(
          artifactScoreTypeToStorage(
            inferScoreType(
              input['specialProp'] as String?,
              input['name'] as String,
            ),
          ),
          c['expected'],
        );
      });
    }
  });

  group('calcPieceScore', () {
    for (final c in _cases(suites, 'calcPieceScore')) {
      test(c['id'] as String, () {
        final input = c['input'] as Map<String, dynamic>;
        final type = artifactScoreTypeFromString(input['type'] as String)!;
        final piece = ArtifactPiece(
          substats: [
            for (final raw in input['substats'] as List)
              ArtifactSubstat(
                stat: (raw as Map)['stat'] as String,
                value: (raw['value'] as num).toDouble(),
              ),
          ],
        );
        expect(calcArtifactPieceScore(piece, type), c['expected']);
      });
    }
  });
}

Map<String, dynamic> _loadGolden() {
  final candidates = [
    File('${Directory.current.path}/../shared/domain-golden/cases.json'),
    File('${Directory.current.path}/shared/domain-golden/cases.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  fail(
    'shared/domain-golden/cases.json not found. '
    'Run flutter test from genshin-builder-mobile/.',
  );
}

List<Map<String, dynamic>> _cases(Map<String, dynamic> suites, String name) {
  final suite = suites[name] as Map<String, dynamic>;
  return (suite['cases'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

CultivationKind _parseKind(String kind) => switch (kind) {
  'character-level' => CultivationKind.characterLevel,
  'weapon-level' => CultivationKind.weaponLevel,
  'talent' => CultivationKind.talent,
  _ => throw ArgumentError('Unknown kind: $kind'),
};

PromoteStage _parsePromote(Map<String, dynamic> json) {
  final costItems = <String, int>{
    for (final e in (json['costItems'] as Map).entries)
      e.key as String: (e.value as num).toInt(),
  };
  return PromoteStage(
    promoteLevel: json['promoteLevel'] as int,
    unlockMaxLevel: json['unlockMaxLevel'] as int,
    costItems: costItems,
    coinCost: json['coinCost'] as int,
  );
}

TalentLevelUpgrade _parseTalentUpgrade(Map<String, dynamic> json) {
  final costItems = <String, int>{
    for (final e in (json['costItems'] as Map).entries)
      e.key as String: (e.value as num).toInt(),
  };
  return TalentLevelUpgrade(
    level: json['level'] as int,
    costItems: costItems,
    coinCost: json['coinCost'] as int,
  );
}
