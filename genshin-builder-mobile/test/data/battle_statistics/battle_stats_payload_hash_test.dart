import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/battle_statistics/battle_stats_payload_hash.dart';
import 'package:genshin_builder_mobile/domain/battle_statistics/battle_statistics.dart';

void main() {
  test('matches the TypeScript canonical-v1 fixture hash', () {
    const expected =
        'sha256:3efecf161f9b715336099c746ada1b8e1d73a029e32b304df23a66344497d3ac';
    final bundle = BattleStatsBundle(
      schemaVersion: 1,
      contentType: BattleStatsContentType.abyss,
      sourceVersion: 'fixture-1',
      seasonId: '2026-07',
      revision: 1,
      payloadHash: expected,
      sourceUpdatedAt: DateTime.parse('2026-07-24T00:00:00.000Z'),
      sampleSize: 1000,
      teams: const [
        RemoteBattleTeam(
          teamKey: '10000001:10000002:10000003:10000004',
          members: ['10000001', '10000002', '10000003', '10000004'],
          usageRate: 0.25,
          usageCount: 250,
          rank: 1,
          side: 'upper',
          stageKey: '12-1',
          sampleSize: 1000,
        ),
      ],
      characters: const [
        RemoteBattleCharacterUsage(
          characterId: '10000001',
          usageRate: 0.5,
          usageCount: 500,
          rank: 1,
          side: 'upper',
          ownershipRate: 0.8,
          usageAmongOwnersRate: 0.625,
          sampleSize: 1000,
        ),
      ],
    );

    expect(const Sha256BattleStatsIntegrityVerifier().matches(bundle), isTrue);
  });
}
