import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/gacha/calendar_event.dart';
import 'package:genshin_builder_mobile/domain/planning/character_farm_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/ley_line_overflow.dart';
import 'package:genshin_builder_mobile/domain/planning/ley_line_overflow_catalog.dart';
import 'package:genshin_builder_mobile/domain/planning/ley_line_overflow_resolve.dart';
import 'package:genshin_builder_mobile/domain/planning/resin_farm_cost_table.dart';
import 'package:genshin_builder_mobile/domain/planning/upgrade_option.dart';
import 'package:genshin_builder_mobile/data/config/config_validators.dart';

LeyLineOverflowEvent _event({
  required DateTime start,
  required DateTime end,
  int limit = 3,
  bool enabled = true,
  List<LeyLineOverflowLeyLineType> types = const [
    LeyLineOverflowLeyLineType.exp,
    LeyLineOverflowLeyLineType.mora,
  ],
}) {
  return LeyLineOverflowEvent(
    eventId: 'e1',
    eventType: 'leyLineOverflow',
    displayName: '地脈の奔流',
    startAt: start.toUtc(),
    endAt: end.toUtc(),
    dailyBonusLimit: limit,
    eligibleLeyLineTypes: types,
    source: 'test',
    enabled: enabled,
  );
}

LeyLineOverflowCatalog _catalog({
  List<LeyLineOverflowEvent> events = const [],
  List<String> matchers = const ['地脈の奔流', 'Ley Line Overflow'],
}) {
  return LeyLineOverflowCatalog(
    version: 1,
    defaults: LeyLineOverflowDefaults(
      displayName: '地脈の奔流',
      dailyBonusLimit: 3,
      nameMatchers: matchers,
    ),
    events: events,
  );
}

ResinFarmCostTable _table() => ResinFarmCostTable.fromJson({
      'version': 2,
      'meta': {
        'naturalResinPerDay': 180,
        'condensedResinValue': 40,
        'synthesisRatio': 3,
        'weekdayLabels': ['月', '火', '水', '木', '金', '土', '日'],
      },
      'kinds': {
        'talentDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
        'weaponDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 2.2},
        'artifactDomain': {'resinPerRun': 20, 'assumedDropsPerRun': 1},
        'weeklyBoss': {'resinPerRun': 30, 'assumedDropsPerRun': 1},
        'worldBoss': {'resinPerRun': 40, 'assumedDropsPerRun': 2},
        'leyLineExp': {
          'resinPerRun': 20,
          'assumedHeroWitEquivalentPerRun': 2.5,
          'contentLabel': '地脈の花（経験値）',
        },
        'leyLineMora': {
          'resinPerRun': 20,
          'assumedMoraPerRun': 60000,
          'contentLabel': 'モラ地脈',
        },
      },
      'zeroResinCategories': [],
    });

void main() {
  final start = DateTime.utc(2026, 7, 1, 4);
  final end = DateTime.utc(2026, 7, 8, 3, 59, 59);

  group('LeyLineOverflowEvent.isActiveAt', () {
    final event = _event(start: start, end: end);

    test('イベント期間内', () {
      expect(event.isActiveAt(DateTime.utc(2026, 7, 3, 12)), isTrue);
    });

    test('イベント期間外', () {
      expect(event.isActiveAt(DateTime.utc(2026, 6, 30, 12)), isFalse);
      expect(event.isActiveAt(DateTime.utc(2026, 7, 9, 0)), isFalse);
    });

    test('開始時刻ちょうど', () {
      expect(event.isActiveAt(start), isTrue);
    });

    test('終了時刻ちょうど', () {
      expect(event.isActiveAt(end), isTrue);
      expect(
        event.isActiveAt(end.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('enabled=false は非開催', () {
      final off = _event(start: start, end: end, enabled: false);
      expect(off.isActiveAt(DateTime.utc(2026, 7, 3)), isFalse);
    });
  });

  group('applyLeyLineOverflowBonus', () {
    LeyLineOverflowStatus activeStatus({int? used}) {
      return LeyLineOverflowStatus(
        isActive: true,
        event: _event(start: start, end: end),
        bonusUsedToday: used,
      );
    }

    test('ボーナス上限未満', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 4,
        resinPerRun: 20,
        status: activeStatus(used: 0),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      // ceil(4/2)=2 bonus → cover 4, remain 0, actual 2
      expect(b.bonusRunsApplied, 2);
      expect(b.normalRunsAfterBonus, 0);
      expect(b.actualRuns, 2);
      expect(b.resinTotal, 40);
      expect(b.isMaxEstimate, isFalse);
    });

    test('ボーナス上限ちょうど', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 6,
        resinPerRun: 20,
        status: activeStatus(used: 0),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      // 3 bonus cover 6
      expect(b.bonusRunsApplied, 3);
      expect(b.normalRunsAfterBonus, 0);
      expect(b.actualRuns, 3);
      expect(b.resinTotal, 60);
    });

    test('ボーナス上限超過', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 9,
        resinPerRun: 20,
        status: activeStatus(used: 0),
        leyLineType: LeyLineOverflowLeyLineType.mora,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      expect(b.normalEquivalentRuns, 9);
      expect(b.bonusRunsApplied, 3);
      expect(b.normalRunsAfterBonus, 3);
      expect(b.actualRuns, 6);
      expect(b.resinTotal, 120);
    });

    test('必要周回数が0', () {
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 0,
          resinPerRun: 20,
          status: activeStatus(),
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNull,
      );
    });

    test('使用済み回数不明は最大適用時の目安', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 9,
        resinPerRun: 20,
        status: activeStatus(),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      expect(b.isMaxEstimate, isTrue);
      expect(b.bonusRunsApplied, 3);
      expect(b.actualRuns, 6);
    });

    test('使用済みを反映した残り枠', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 9,
        resinPerRun: 20,
        status: activeStatus(used: 2),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      // remaining 1 → cover 2, remain 7, actual 8
      expect(b.remainingBonusCapacity, 1);
      expect(b.bonusRunsApplied, 1);
      expect(b.normalRunsAfterBonus, 7);
      expect(b.actualRuns, 8);
      expect(b.isMaxEstimate, isFalse);
    });

    test('期間外は null（通常計算）', () {
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 9,
          resinPerRun: 20,
          status: activeStatus(),
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 8, 1),
        ),
        isNull,
      );
    });

    test('対象外タイプは null', () {
      final status = LeyLineOverflowStatus(
        isActive: true,
        event: _event(
          start: start,
          end: end,
          types: const [LeyLineOverflowLeyLineType.exp],
        ),
      );
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 9,
          resinPerRun: 20,
          status: status,
          leyLineType: LeyLineOverflowLeyLineType.mora,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNull,
      );
    });
  });

  group('resolveLeyLineOverflowStatus', () {
    test('カレンダー名称マッチで開催中', () {
      final status = resolveLeyLineOverflowStatus(
        catalog: _catalog(),
        nowUtc: DateTime.utc(2026, 7, 3),
        calendarEvents: [
          CalendarEvent(
            id: 'cal1',
            name: '地脈の奔流',
            description: '',
            typeName: 'Event',
            start: start,
            end: end,
          ),
        ],
      );
      expect(status.isActive, isTrue);
      expect(status.event?.source, 'calendarApi');
      expect(status.event?.displayName, '地脈の奔流');
    });

    test('設定フォールバックの開催期間', () {
      final status = resolveLeyLineOverflowStatus(
        catalog: _catalog(events: [_event(start: start, end: end)]),
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      expect(status.isActive, isTrue);
      expect(status.event?.source, 'test');
    });

    test('イベント情報取得失敗は開催中としない', () {
      final status = resolveLeyLineOverflowStatus(
        catalog: _catalog(),
        nowUtc: DateTime.utc(2026, 7, 3),
        catalogLoadFailed: true,
      );
      expect(status.isActive, isFalse);
      expect(status.resolveFailed, isTrue);
    });

    test('タイムゾーン・サーバー地域差（JST now → UTC 比較）', () {
      // JST 2026-07-01 13:00 = UTC 2026-07-01 04:00 = start
      final jst = DateTime.parse('2026-07-01T13:00:00+09:00');
      final status = resolveLeyLineOverflowStatus(
        catalog: _catalog(events: [_event(start: start, end: end)]),
        nowUtc: jst.toUtc(),
      );
      expect(status.isActive, isTrue);

      // JST 2026-07-08 13:00:00 = UTC 2026-07-08 04:00 > end 03:59:59
      final after = DateTime.parse('2026-07-08T13:00:00+09:00').toUtc();
      final status2 = resolveLeyLineOverflowStatus(
        catalog: _catalog(events: [_event(start: start, end: end)]),
        nowUtc: after,
      );
      expect(status2.isActive, isFalse);
    });
  });

  group('buildCharacterFarmPlan + overflow', () {
    final table = _table();
    final active = LeyLineOverflowStatus(
      isActive: true,
      event: _event(start: start, end: end),
    );

    test('経験値本地脈：通常9回→実際6回', () {
      // ceil(x/2.5)=9 → x in (20, 22.5] → use 21 books
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
          ),
        ],
        table: table,
        leyLineOverflowStatus: active,
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      final exp =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.leyLineOverflow, isNotNull);
      expect(exp.leyLineOverflow!.normalEquivalentRuns, 9);
      expect(exp.leyLineOverflow!.actualRuns, 6);
      expect(exp.runsExpected, 6);
      expect(exp.resinTotal, 120);
      expect(exp.showLeyLineOverflowBadge, isTrue);
      expect(exp.leyLineOverflow!.eventDisplayName, '地脈の奔流');
      expect(exp.leyLineOverflow!.isMaxEstimate, isTrue);
    });

    test('モラ地脈にボーナス適用', () {
      // 720000 / 60000 = 12 normal → 3 bonus cover 6, remain 6, actual 9, resin 180
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            moraCost: 720000,
          ),
        ],
        table: table,
        leyLineOverflowStatus: active,
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      final mora =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineMora);
      expect(mora.leyLineOverflow!.normalEquivalentRuns, 12);
      expect(mora.leyLineOverflow!.bonusRunsApplied, 3);
      expect(mora.leyLineOverflow!.normalRunsAfterBonus, 6);
      expect(mora.runsExpected, 9);
      expect(mora.resinTotal, 180);
    });

    test('期間外は通常計算・バッジなし', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
          ),
        ],
        table: table,
        leyLineOverflowStatus: active,
        nowUtc: DateTime.utc(2026, 8, 1),
      );
      final exp =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.leyLineOverflow, isNull);
      expect(exp.runsExpected, 9);
      expect(exp.resinTotal, 180);
      expect(exp.showLeyLineOverflowBadge, isFalse);
    });

    test('開催中表示と計算結果の整合性（文字ラベル用フィールド）', () {
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
            moraCost: 180000,
          ),
        ],
        table: table,
        leyLineOverflowStatus: active,
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      for (final s in plan.sections.where(
        (s) =>
            s.kind == ResinFarmKind.leyLineExp ||
            s.kind == ResinFarmKind.leyLineMora,
      )) {
        final o = s.leyLineOverflow!;
        expect(o.eventDisplayName, isNotEmpty);
        expect(s.runsExpected, o.actualRuns);
        expect(s.resinTotal, o.resinTotal);
        expect(
          o.actualRuns,
          o.bonusRunsApplied + o.normalRunsAfterBonus,
        );
        expect(
          o.normalEquivalentRuns,
          lessThanOrEqualTo(
            o.bonusRunsApplied * o.rewardMultiplier + o.normalRunsAfterBonus,
          ),
        );
      }
    });

    test('取得失敗ステータスでは通常計算', () {
      const failed = LeyLineOverflowStatus(
        isActive: false,
        resolveFailed: true,
      );
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
          ),
        ],
        table: table,
        leyLineOverflowStatus: failed,
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      final exp =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.leyLineOverflow, isNull);
      expect(exp.resinTotal, 180);
    });
  });

  group('validateLeyLineOverflowEventsJson', () {
    test('accepts local asset shape', () {
      expect(
        () => validateLeyLineOverflowEventsJson({
          'version': 1,
          'defaults': {
            'displayName': '地脈の奔流',
            'dailyBonusLimit': 3,
            'nameMatchers': ['地脈の奔流'],
          },
          'events': [],
        }),
        returnsNormally,
      );
    });
  });

  group('UI契約: 色だけに依存しない', () {
    test('開催中は必ずイベント表示名を持つ', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 9,
        resinPerRun: 20,
        status: LeyLineOverflowStatus(
          isActive: true,
          event: _event(start: start, end: end),
        ),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      expect(b.eventDisplayName, '地脈の奔流');
      // UI は `${eventDisplayName} 開催中` を必ず描画する
      expect('${b.eventDisplayName} 開催中', '地脈の奔流 開催中');
    });
  });

  group('境界・残り回数マトリクス', () {
    LeyLineOverflowStatus active({int? used}) => LeyLineOverflowStatus(
          isActive: true,
          event: _event(start: start, end: end),
          bonusUsedToday: used,
        );

    test('開始時刻直前は非開催', () {
      final event = _event(start: start, end: end);
      expect(
        event.isActiveAt(start.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('終了時刻直前は開催中', () {
      final event = _event(start: start, end: end);
      expect(
        event.isActiveAt(end.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('不正な開催期間（end < start）は非開催', () {
      final bad = _event(start: end, end: start);
      expect(bad.isActiveAt(DateTime.utc(2026, 7, 3)), isFalse);
      expect(
        LeyLineOverflowEventFromJson.parse(
          {
            'eventId': 'bad',
            'startAt': '2026-07-08T00:00:00Z',
            'endAt': '2026-07-01T00:00:00Z',
          },
          defaults: const LeyLineOverflowDefaults(
            displayName: '地脈の奔流',
            dailyBonusLimit: 3,
            nameMatchers: ['地脈の奔流'],
          ),
        ),
        isNull,
      );
    });

    for (final n in [1, 2, 3, 4, 9]) {
      test('通常換算$n回（残り3）', () {
        final b = applyLeyLineOverflowBonus(
          normalEquivalentRuns: n,
          resinPerRun: 20,
          status: active(used: 0),
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 7, 3),
        )!;
        final useful = (n + 1) ~/ 2;
        final bonus = useful < 3 ? useful : 3;
        final covered = bonus * 2;
        final remain = n - covered;
        final normal = remain < 0 ? 0 : remain;
        expect(b.bonusRunsApplied, bonus);
        expect(b.actualRuns, bonus + normal);
        expect(b.resinTotal, b.actualRuns * 20);
      });
    }

    for (final used in [0, 1, 2, 3]) {
      test('ボーナス使用済み$used → 残り${3 - used}', () {
        final b = applyLeyLineOverflowBonus(
          normalEquivalentRuns: 9,
          resinPerRun: 20,
          status: active(used: used),
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 7, 3),
        )!;
        expect(b.remainingBonusCapacity, 3 - used);
        expect(b.isMaxEstimate, isFalse);
        expect(active(used: used).remainingCountKnown, isTrue);
      });
    }

    test('ボーナス残り0は通常周回のみ', () {
      final b = applyLeyLineOverflowBonus(
        normalEquivalentRuns: 9,
        resinPerRun: 20,
        status: active(used: 3),
        leyLineType: LeyLineOverflowLeyLineType.exp,
        nowUtc: DateTime.utc(2026, 7, 3),
      )!;
      expect(b.bonusRunsApplied, 0);
      expect(b.actualRuns, 9);
      expect(b.resinTotal, 180);
    });

    test('経験値本のみ対象', () {
      final status = LeyLineOverflowStatus(
        isActive: true,
        event: _event(
          start: start,
          end: end,
          types: const [LeyLineOverflowLeyLineType.exp],
        ),
      );
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 4,
          resinPerRun: 20,
          status: status,
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNotNull,
      );
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 4,
          resinPerRun: 20,
          status: status,
          leyLineType: LeyLineOverflowLeyLineType.mora,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNull,
      );
    });

    test('モラのみ対象', () {
      final status = LeyLineOverflowStatus(
        isActive: true,
        event: _event(
          start: start,
          end: end,
          types: const [LeyLineOverflowLeyLineType.mora],
        ),
      );
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 4,
          resinPerRun: 20,
          status: status,
          leyLineType: LeyLineOverflowLeyLineType.mora,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNotNull,
      );
      expect(
        applyLeyLineOverflowBonus(
          normalEquivalentRuns: 4,
          resinPerRun: 20,
          status: status,
          leyLineType: LeyLineOverflowLeyLineType.exp,
          nowUtc: DateTime.utc(2026, 7, 3),
        ),
        isNull,
      );
    });

    test('濃縮樹脂はボーナス対象外フラグ', () {
      final event = _event(start: start, end: end);
      expect(event.condensedResinEligible, isFalse);
    });

    test('所持差し引き後の経験値にボーナス適用', () {
      final table = _table();
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 30},
            ownedMaterials: {'104003': 9},
            inventoryStatus: InventoryStatus.ownedInsufficient,
          ),
        ],
        table: table,
        leyLineOverflowStatus: active(),
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      // shortage 21 → normal 9 → actual 6
      final exp =
          plan.sections.singleWhere((s) => s.kind == ResinFarmKind.leyLineExp);
      expect(exp.materials.single.shortage, 21);
      expect(exp.leyLineOverflow!.normalEquivalentRuns, 9);
      expect(exp.resinTotal, 120);
    });

    test('イベント中の合計樹脂はセクション合算と一致', () {
      final table = _table();
      final plan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
            moraCost: 720000,
          ),
        ],
        table: table,
        leyLineOverflowStatus: active(),
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      final sum = plan.sections.fold<int>(0, (s, x) => s + x.resinTotal);
      expect(plan.totalResin, sum);
      // exp 120 + mora 180
      expect(plan.totalResin, 300);
    });

    test('通常時の既存結果との一致（非開催）', () {
      final table = _table();
      final inactivePlan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
            moraCost: 720000,
          ),
        ],
        table: table,
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      final failedPlan = buildCharacterFarmPlan(
        characterId: 'c1',
        options: [
          const UpgradeOption(
            optionId: 'o1',
            characterId: 'c1',
            optionType: 'level',
            expItemCost: {'104003': 21},
            moraCost: 720000,
          ),
        ],
        table: table,
        leyLineOverflowStatus: const LeyLineOverflowStatus(
          isActive: false,
          resolveFailed: true,
        ),
        nowUtc: DateTime.utc(2026, 7, 3),
      );
      expect(inactivePlan.totalResin, failedPlan.totalResin);
      expect(inactivePlan.totalResin, 180 + 240);
    });

    test('remainingCountKnown と isMaxEstimate', () {
      expect(active().remainingCountKnown, isFalse);
      expect(active().isMaxEstimate, isTrue);
      expect(active(used: 1).remainingCountKnown, isTrue);
      expect(active(used: 1).isMaxEstimate, isFalse);
    });
  });
}
