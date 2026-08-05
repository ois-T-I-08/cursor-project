import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/daily_plan/daily_plan_proposal_codec.dart';

void main() {
  test('Webと同じdaily plan schema v1 fixtureをparseする', () {
    final fixture = _loadFixture();
    final proposal = parseDailyPlanProposal(
      fixture,
      allowedTaskIds: const {'wd_freedom', 'goal_level', 'goal_talent_locked'},
    );

    expect(proposal, isNotNull);
    expect(proposal!.schemaVersion, 1);
    expect(proposal.recommendations.map((item) => item.taskId), [
      'wd_freedom',
      'goal_level',
    ]);
    expect(
      proposal.proposalFingerprint,
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    );
  });

  test('schemaVersion不一致をfail-closedにする', () {
    final fixture = _loadFixture()..['schemaVersion'] = 2;
    expect(
      parseDailyPlanProposal(
        fixture,
        allowedTaskIds: const {
          'wd_freedom',
          'goal_level',
          'goal_talent_locked',
        },
      ),
      isNull,
    );
  });
}

Map<String, dynamic> _loadFixture() {
  final candidates = [
    File(
      '${Directory.current.path}/../shared/domain-golden/'
      'daily-plan-proposal-v1.json',
    ),
    File(
      '${Directory.current.path}/shared/domain-golden/'
      'daily-plan-proposal-v1.json',
    ),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    }
  }
  fail('shared daily-plan proposal fixture not found');
}
