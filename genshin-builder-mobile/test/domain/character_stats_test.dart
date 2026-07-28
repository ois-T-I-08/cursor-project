import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/character_stats.dart';
import 'package:genshin_builder_mobile/domain/models/artifact_state.dart';

/// メインステータス未設定（完全に空）の聖遺物状態
ArtifactState blankArtifacts() => {
  for (final slot in ArtifactSlotKey.values) slot: const ArtifactPiece(),
};

void main() {
  group('artifactMainStatValue', () {
    test('★5 main stat interpolation', () {
      expect(artifactMainStatValue('HP', 20), 4780);
      expect(artifactMainStatValue('HP', 0), 717);
      expect(artifactMainStatValue('会心率', 20), 31.1);
      expect(artifactMainStatValue('攻撃力%', 20), 46.6);
      expect(artifactMainStatValue('未知ステータス', 20), 0);
    });
  });

  group('WeaponStatsData.statsAtLevel', () {
    final weapon = WeaponStatsData(
      props: [
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_ATTACK',
          initValue: 40,
          curveValues: List.filled(90, 2.0),
        ),
        StatCurveProp(
          propType: 'FIGHT_PROP_CRITICAL_HURT',
          initValue: 0.1,
          curveValues: List.filled(90, 1.0),
        ),
      ],
      promotes: const [
        StatPromote(promoteLevel: 0, unlockMaxLevel: 20, addProps: {}),
        StatPromote(
          promoteLevel: 1,
          unlockMaxLevel: 40,
          addProps: {'FIGHT_PROP_BASE_ATTACK': 25},
        ),
      ],
    );

    test('applies curve and promote bonus', () {
      final at20 = weapon.statsAtLevel(20);
      expect(at20.baseAttack, 80); // 40 * 2.0（promote 0 加算なし）
      expect(at20.subStatProp, 'FIGHT_PROP_CRITICAL_HURT');
      expect(at20.subStatValue, 0.1);

      final at40 = weapon.statsAtLevel(40);
      expect(at40.baseAttack, 105); // 40 * 2.0 + 25
    });
  });

  group('computeCharacterStats', () {
    final avatarStats = AvatarStatsData(
      props: [
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_HP',
          initValue: 1000,
          curveValues: List.filled(90, 1.0),
        ),
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_ATTACK',
          initValue: 100,
          curveValues: List.filled(90, 1.0),
        ),
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_DEFENSE',
          initValue: 50,
          curveValues: List.filled(90, 1.0),
        ),
      ],
      promotes: const [
        StatPromote(promoteLevel: 0, unlockMaxLevel: 20, addProps: {}),
        StatPromote(
          promoteLevel: 1,
          unlockMaxLevel: 40,
          addProps: {
            'FIGHT_PROP_BASE_HP': 500,
            'FIGHT_PROP_CRITICAL_HURT': 0.384,
          },
        ),
      ],
    );

    test('combines base, promote, weapon, artifacts', () {
      final artifacts = blankArtifacts();
      artifacts[ArtifactSlotKey.flower] = const ArtifactPiece(
        mainStat: 'HP',
        level: 20,
        substats: [ArtifactSubstat(stat: '会心率', value: 10)],
      );

      final stats = computeCharacterStats(
        avatarStats: avatarStats,
        element: 'pyro',
        level: 40,
        ascension: 1,
        weapon: const WeaponLevelStats(
          baseAttack: 200,
          subStatProp: 'FIGHT_PROP_CRITICAL',
          subStatValue: 0.10,
        ),
        artifacts: artifacts,
      );

      // HP: (1000*1.0 + 500) + 4780(花メイン) = 6280
      expect(stats[StatKey.hp], 6280);
      // 攻撃力: 100 + 200(武器) = 300
      expect(stats[StatKey.atk], 300);
      expect(stats[StatKey.def], 50);
      // 会心率: 5(基礎) + 10(武器サブ) + 10(聖遺物サブ) = 25
      expect(stats[StatKey.critRate], 25.0);
      // 会心ダメ: 50(基礎) + 38.4(突破) = 88.4
      expect(stats[StatKey.critDmg], 88.4);
      expect(stats[StatKey.er], 100.0);
    });

    test('applies 2-piece set effect ATK%', () {
      final artifacts = blankArtifacts();
      final stats = computeCharacterStats(
        avatarStats: avatarStats,
        element: 'pyro',
        level: 1,
        ascension: 0,
        artifacts: artifacts,
        activeSetEffects: const ['攻撃力+18%'],
      );
      // base atk 100 * 1.18 = 118
      expect(stats[StatKey.atk], 118);
    });

    test('ascension 0 has no promote bonus', () {
      final stats = computeCharacterStats(
        avatarStats: avatarStats,
        element: 'pyro',
        level: 20,
        ascension: 0,
        weapon: null,
        artifacts: blankArtifacts(),
      );
      expect(stats[StatKey.hp], 1000);
      expect(stats[StatKey.critDmg], 50.0);
    });
  });

  group('buildStatDeltaRows / format', () {
    test('delta rows and formatting', () {
      final current =
          <StatKey, double>{for (final k in StatKey.values) k: 0}
            ..[StatKey.atk] = 1000
            ..[StatKey.critRate] = 50.0;
      final simulated =
          <StatKey, double>{for (final k in StatKey.values) k: 0}
            ..[StatKey.atk] = 1350
            ..[StatKey.critRate] = 62.4;

      final rows = buildStatDeltaRows(
        current: current,
        simulated: simulated,
        elementLabel: '炎元素ダメージ',
      );

      final atk = rows.firstWhere((r) => r.key == StatKey.atk);
      expect(atk.delta, 350);
      expect(formatStatDelta(StatKey.atk, atk.delta), '+350');

      final cr = rows.firstWhere((r) => r.key == StatKey.critRate);
      expect(formatStatDelta(StatKey.critRate, cr.delta), '+12.4%');
      expect(formatStatValue(StatKey.critRate, cr.simulated), '62.4%');

      final elem = rows.firstWhere((r) => r.key == StatKey.elemDmg);
      expect(elem.label, '炎元素ダメージ');
      expect(elem.hasChange, isFalse);
    });
  });

  group('computeCharacterBaseStats / ascension helpers', () {
    final avatar = AvatarStatsData(
      props: [
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_HP',
          initValue: 1000,
          curveValues: List.filled(90, 1.0),
        ),
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_ATTACK',
          initValue: 50,
          curveValues: List.filled(90, 1.0),
        ),
        StatCurveProp(
          propType: 'FIGHT_PROP_BASE_DEFENSE',
          initValue: 40,
          curveValues: List.filled(90, 1.0),
        ),
      ],
      promotes: const [
        StatPromote(promoteLevel: 0, unlockMaxLevel: 20, addProps: {}),
        StatPromote(
          promoteLevel: 1,
          unlockMaxLevel: 40,
          addProps: {'FIGHT_PROP_BASE_HP': 100, 'FIGHT_PROP_CRITICAL': 0.048},
        ),
        StatPromote(
          promoteLevel: 6,
          unlockMaxLevel: 90,
          addProps: {'FIGHT_PROP_BASE_HP': 600, 'FIGHT_PROP_CRITICAL': 0.192},
        ),
      ],
    );

    test('base stats include promote flat bonuses', () {
      final base = computeCharacterBaseStats(
        avatarStats: avatar,
        level: 40,
        ascension: 1,
      );
      expect(base.hp, 1100);
      expect(base.atk, 50);
      expect(base.def, 40);
    });

    test('ascension bonus excludes base props', () {
      final bonuses = ascensionBonusProps(
        findPromoteByLevel(avatar.promotes, 6),
      );
      expect(bonuses.keys, ['FIGHT_PROP_CRITICAL']);
      expect(formatFightPropValue('FIGHT_PROP_CRITICAL', 0.192), '19.2%');
      expect(
        formatAscensionStageLabel(promoteLevel: 6, promotes: avatar.promotes),
        isNot(equals('未突破')),
      );
    });
  });
}
