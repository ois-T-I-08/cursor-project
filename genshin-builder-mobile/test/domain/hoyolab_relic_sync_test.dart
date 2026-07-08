import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/hoyolab/models/game_record.dart';
import 'package:genshin_builder_mobile/domain/artifact_config.dart';
import 'package:genshin_builder_mobile/domain/hoyolab_relic_sync.dart';
import 'package:genshin_builder_mobile/domain/hoyolab_stat_normalize.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';

void main() {
  group('parseGameRecordPropertyMap', () {
    test('maps property_type id to display name', () {
      final map = parseGameRecordPropertyMap({
        '20': {
          'property_type': 20,
          'name': '会心率',
          'filter_name': 'FIGHT_PROP_CRITICAL',
        },
        '46': {
          'property_type': 46,
          'name': '攻击力',
          'filter_name': 'FIGHT_PROP_ATTACK_PERCENT',
        },
      });

      expect(map[20]?.name, '会心率');
      expect(map[46]?.filterName, 'FIGHT_PROP_ATTACK_PERCENT');
    });
  });

  group('GameRecordRelic.fromJson', () {
    test('resolves main_property via property_map', () {
      final propertyMap = parseGameRecordPropertyMap({
        '22': {
          'property_type': 22,
          'name': '暴击率',
          'filter_name': 'FIGHT_PROP_CRITICAL',
        },
      });

      final relic = GameRecordRelic.fromJson(
        {
          'id': 1,
          'name': '冠',
          'pos_name': '理之冠',
          'level': 20,
          'set': {'name': '深林の記憶'},
          'main_property': {
            'property_type': 22,
            'value': '31.2%',
          },
        },
        propertyMap: propertyMap,
      );

      expect(relic.mainStat?.label, '暴击率');
      expect(relic.mainStat?.value, '31.2%');
    });
  });

  group('mergeRelicsFromHoyolab', () {
    test('updates set name and level from API', () {
      final local = createEmptyArtifactState();
      final merged = mergeRelicsFromHoyolab(
        local: local,
        relics: const [
          GameRecordRelic(
            id: '1',
            name: '花',
            posName: '生の花',
            level: 20,
            setName: '深林の記憶',
          ),
        ],
      );

      expect(merged[ArtifactSlotKey.flower]!.setName, '深林の記憶');
      expect(merged[ArtifactSlotKey.flower]!.level, 20);
    });

    test('syncs normalized main stat from API', () {
      final local = createEmptyArtifactState();
      final merged = mergeRelicsFromHoyolab(
        local: local,
        relics: const [
          GameRecordRelic(
            id: '3',
            name: '冠',
            posName: '理之冠',
            level: 20,
            setName: '深林の記憶',
            mainStat: GameRecordProp(label: '暴击率', value: '31.2%'),
          ),
        ],
      );

      expect(merged[ArtifactSlotKey.circlet]!.mainStat, '会心率');
    });

    test('prefills substats only when local is empty', () {
      final local = createEmptyArtifactState();
      local[ArtifactSlotKey.plume] = const ArtifactPiece(
        setName: '旧セット',
        level: 16,
        substats: [ArtifactSubstat(stat: '会心率', value: 3.5)],
      );

      final merged = mergeRelicsFromHoyolab(
        local: local,
        relics: const [
          GameRecordRelic(
            id: '2',
            name: '羽',
            posName: '死の羽',
            level: 20,
            setName: '深林の記憶',
            subStats: [
              GameRecordProp(label: '攻撃力%', value: '5.8'),
            ],
          ),
        ],
      );

      expect(merged[ArtifactSlotKey.plume]!.setName, '深林の記憶');
      expect(merged[ArtifactSlotKey.plume]!.level, 20);
      expect(merged[ArtifactSlotKey.plume]!.substats.length, 1);
      expect(merged[ArtifactSlotKey.plume]!.substats.first.stat, '会心率');
    });
  });

  group('normalizeMainStatForSlot', () {
    test('maps Chinese crit rate label to app label', () {
      expect(
        normalizeMainStatForSlot('暴击率', ArtifactSlotKey.circlet),
        '会心率',
      );
    });
  });

  group('buildArtifactSummary', () {
    test('shows set counts and levels', () {
      final state = createEmptyArtifactState();
      for (final slot in ArtifactSlotKey.values) {
        state[slot] = ArtifactPiece(setName: '深林の記憶', level: 20);
      }

      final summary = buildArtifactSummary(state);
      expect(summary, contains('深林の記憶 ×4'));
      expect(summary, contains('花+20'));
    });
  });
}
