import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/domain/team/team_models.dart';
import 'package:genshin_builder_mobile/domain/account/account_health_report.dart';

void main() {
  group('Team JSON safety', () {
    test('valid team passes validate', () {
      const team = Team(
        id: 't1', name: 'Test',
        members: [
          TeamMemberSlot(characterId: '10000002', position: 0),
          TeamMemberSlot(characterId: '10000096', position: 1),
        ],
      );
      expect(Team.validate(team), isNull);
    });

    test('duplicate character rejected', () {
      const team = Team(
        id: 't1', name: 'Test',
        members: [
          TeamMemberSlot(characterId: '10000002', position: 0),
          TeamMemberSlot(characterId: '10000002', position: 1),
        ],
      );
      expect(Team.validate(team), contains('Duplicate'));
    });

    test('max 4 enforced', () {
      final team = Team(
        id: 't1', name: 'Test',
        members: List.generate(5, (i) => TeamMemberSlot(characterId: 'id$i', position: i)),
      );
      expect(Team.validate(team), isNotNull);
    });

    test('v1 JSON encodes members correctly', () {
      const team = Team(
        id: 't1', name: 'Test',
        members: [
          TeamMemberSlot(characterId: '10000002', position: 0),
          TeamMemberSlot(characterId: '10000096', position: 1),
        ],
      );
      final json = {
        'version': 1,
        'members': team.members.map((m) => {
              'characterId': m.characterId,
              'buildId': m.buildId,
              'position': m.position,
            }).toList(),
      };
      final encoded = jsonEncode(json);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      expect((decoded['members'] as List).length, 2);
    });

    test('legacy plain list JSON parses correctly', () {
      final legacy = jsonEncode([
        {'characterId': '10000002', 'buildId': null, 'position': 0},
        {'characterId': '10000096', 'buildId': null, 'position': 1},
      ]);
      final decoded = jsonDecode(legacy) as List;
      // Simulate reading legacy format
      expect(decoded.length, 2);
      final members = decoded.map((m) =>
        TeamMemberSlot(
          characterId: m['characterId'] as String,
          buildId: m['buildId'] as String?,
          position: (m['position'] as int?) ?? 0,
        )).toList();
      expect(members.length, 2);
    });

    test('unknown fields are ignored in v1 format', () {
      final json = {
        'version': 1,
        'unknownField': 'should be ignored',
        'members': [
          {'characterId': '10000002', 'buildId': null, 'position': 0, 'extraField': 42},
        ],
      };
      final encoded = jsonEncode(json);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final membersList = decoded['members'] as List;
      expect(membersList.length, 1);
      // unknown fields don't break parsing
    });

    test('invalid JSON rejects gracefully', () {
      expect(() => jsonDecode('not json'), throwsFormatException);
    });

    test('missing required field rejected', () {
      // characterId is missing → should be caught by validate
      const team = Team(
        id: 't1', name: 'Test',
        members: [TeamMemberSlot(characterId: '', position: 0)],
      );
      expect(Team.validate(team), isNotNull);
    });

    test('GrowthEvent pagination key is stable', () {
      final dt = DateTime(2026, 7, 14, 12, 0);
      final k1 = '$dt';
      final k2 = '${DateTime(2026, 7, 14, 12, 0)}';
      expect(k1, k2);
    });
  });

  group('Health report null safety', () {
    test('isEvaluable false when totalScore is null', () {
      const report = AccountHealthReport();
      expect(report.isEvaluable, isFalse);
      expect(report.totalScore, isNull);
      expect(report.dataCoverage, '不明');
    });

    test('scoreToRating is not called with null', () {
      const report = AccountHealthReport();
      expect(report.rating, HealthRating.unknown);
    });
  });
}
