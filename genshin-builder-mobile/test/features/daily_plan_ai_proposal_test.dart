import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/daily_plan_notifications/daily_plan_user_scope.dart';
import 'package:genshin_builder_mobile/application/planning/apply_daily_plan_enrichment.dart';
import 'package:genshin_builder_mobile/application/planning/build_deterministic_daily_plan_proposal.dart';
import 'package:genshin_builder_mobile/application/planning/daily_plan_fingerprint.dart';
import 'package:genshin_builder_mobile/data/daily_plan/daily_plan_proposal_store.dart';
import 'package:genshin_builder_mobile/data/db/app_database_facade.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_item_key.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_proposal.dart';
import 'package:genshin_builder_mobile/domain/recommendation/recommendation.dart';
import 'package:genshin_builder_mobile/features/growth/daily_plan_screen.dart';
import 'package:genshin_builder_mobile/features/growth/widgets/daily_plan_proposal_panel.dart';
import 'package:genshin_builder_mobile/features/growth/widgets/daily_plan_task_tile.dart';
import 'package:genshin_builder_mobile/providers/app_providers.dart';
import 'package:genshin_builder_mobile/providers/daily_plan_completion_providers.dart';
import 'package:genshin_builder_mobile/providers/growth_providers.dart';

void main() {
  group('DailyPlanProposalPanel', () {
    testWidgets(
      'emphasizes one primary task, limits next tasks to two, and hides the rest',
      (tester) async {
        final items = List.generate(11, _item);
        final deferred = _item(99, title: '未開放の育成', availableToday: false);
        final proposal = _proposal(
          items,
          summary: '長いAI全体説明は最初から表示しません',
          reason: '長いAI理由も最初から表示しません',
          deferredTaskIds: [deferred.id],
        );

        await _pumpPanel(
          tester,
          proposal: proposal,
          items: [...items, deferred],
        );

        expect(
          find.byKey(const Key('daily-plan-primary-card')),
          findsOneWidget,
        );
        expect(find.text('今日の最優先'), findsOneWidget);
        expect(find.text('天賦 Lv.7 → Lv.9'), findsOneWidget);
        expect(_findKeyPrefix('daily-plan-next-task-'), findsNWidgets(2));
        expect(_findKeyPrefix('daily-plan-extra-task-'), findsNothing);
        expect(find.text('ほか8件を見る'), findsOneWidget);
        expect(
          _findKeyPrefix('daily-plan-reason-badge-${items.first.id}-'),
          findsNWidgets(2),
        );
        expect(find.text(proposal.summary), findsNothing);
        expect(find.text('長いAI理由も最初から表示しません'), findsNothing);
        expect(find.text(deferred.title), findsNothing);
        expect(find.textContaining('do_today'), findsNothing);
        expect(find.textContaining('confidence'), findsNothing);
        expect(find.textContaining('score'), findsNothing);

        await tester.ensureVisible(
          find.byKey(const Key('daily-plan-more-recommendations')),
        );
        await tester.tap(
          find.byKey(const Key('daily-plan-more-recommendations')),
        );
        await tester.pump();

        expect(_findKeyPrefix('daily-plan-next-task-'), findsNWidgets(2));
        expect(_findKeyPrefix('daily-plan-extra-task-'), findsNWidgets(8));
      },
    );

    testWidgets('shows AI free text and metadata only after expansion', (
      tester,
    ) async {
      final item = _item(0);
      const reason = '本日入手でき、目標までの差が小さいため最初に選びました';
      final proposal = _proposal(
        [item],
        summary: '今日は天賦素材を優先すると効率的です',
        reason: reason,
      );

      await _pumpPanel(tester, proposal: proposal, items: [item]);

      expect(find.text(proposal.summary), findsNothing);
      expect(find.text(reason), findsNothing);
      expect(find.textContaining('提案方法:'), findsNothing);

      await tester.ensureVisible(find.text('AIがこの順番にした理由'));
      await tester.tap(find.text('AIがこの順番にした理由'));
      await tester.pumpAndSettle();

      expect(find.text(proposal.summary), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(find.textContaining('提案方法: AI提案'), findsOneWidget);
      expect(find.textContaining('生成時刻:'), findsOneWidget);
    });

    testWidgets('keeps deferred tasks collapsed and uses natural Japanese', (
      tester,
    ) async {
      final primary = _item(0);
      final deferred = [
        _item(1, title: '時間超過', estimatedMinutes: 90),
        _item(2, title: '条件不足', availableToday: false),
        _item(
          3,
          title: '情報不足',
          missingData: const [MissingData.materialInventory],
        ),
        _item(4, title: '後日でよい', reasons: const ['後日でも入手可能']),
        _item(5, title: '低順位'),
      ];
      final proposal = _proposal([
        primary,
      ], deferredTaskIds: deferred.map((item) => item.id).toList());

      await _pumpPanel(
        tester,
        proposal: proposal,
        items: [primary, ...deferred],
        availableMinutes: 30,
      );

      expect(find.text('今日は見送る項目'), findsOneWidget);
      for (final item in deferred) {
        expect(find.text(item.title), findsNothing);
      }

      await tester.ensureVisible(find.text('今日は見送る項目'));
      await tester.tap(find.text('今日は見送る項目'));
      await tester.pumpAndSettle();

      expect(find.text('今日の時間に入りません'), findsOneWidget);
      expect(find.text('必要な素材または条件が不足しています'), findsOneWidget);
      expect(find.text('判断に必要な情報が不足しています'), findsOneWidget);
      expect(find.text('今日限定ではありません'), findsOneWidget);
      expect(find.text('ほかの育成を優先します'), findsOneWidget);
      for (final code in const [
        'not_enough_time',
        'lower_priority',
        'deadline_later',
        'blocked',
        'missing_information',
      ]) {
        expect(find.textContaining(code), findsNothing);
      }
    });

    testWidgets('uses natural fallback and empty-state copy', (tester) async {
      final item = _item(0);
      await _pumpPanel(
        tester,
        proposal: _proposal([
          item,
        ], source: DailyPlanRecommendationSource.deterministicFallback),
        items: [item],
      );
      expect(find.text('期限と育成効率から提案しています'), findsOneWidget);
      expect(find.textContaining('deterministicFallback'), findsNothing);

      await _pumpPanel(tester, proposal: _proposal(const []), items: const []);
      expect(find.text('今日は優先する育成がありません'), findsOneWidget);
      expect(find.text('育成目標やブックマークを追加すると提案できます'), findsOneWidget);
    });

    testWidgets('handles one long task at large text size in light and dark', (
      tester,
    ) async {
      final item = _item(
        0,
        title: 'とても長いキャラクター名の通常攻撃天賦を目標レベルまで一気に育成するための素材を集める',
      );
      final proposal = _proposal([item]);

      for (final brightness in [Brightness.light, Brightness.dark]) {
        await _pumpPanel(
          tester,
          proposal: proposal,
          items: [item],
          textScale: 2,
          brightness: brightness,
          viewport: const Size(320, 700),
        );
        expect(
          find.byKey(const Key('daily-plan-primary-card')),
          findsOneWidget,
        );
        expect(_findKeyPrefix('daily-plan-next-task-'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('never promotes an unavailable recommendation', (tester) async {
      final unavailable = _item(0, title: '今日は入手不可', availableToday: false);
      final available = _item(1, title: '今日進められる育成');
      final proposal = _proposal([unavailable, available]);

      await _pumpPanel(
        tester,
        proposal: proposal,
        items: [unavailable, available],
      );

      final primary = find.descendant(
        of: find.byKey(const Key('daily-plan-primary-card')),
        matching: find.text('今日進められる育成'),
      );
      expect(primary, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('daily-plan-primary-card')),
          matching: find.text('今日は入手不可'),
        ),
        findsNothing,
      );
    });

    testWidgets('exposes the requested primary and secondary actions', (
      tester,
    ) async {
      final items = [_item(0), _item(1)];
      var openCount = 0;
      var addCount = 0;
      var regenerateCount = 0;
      var closeCount = 0;
      await _pumpPanel(
        tester,
        proposal: _proposal(items),
        items: items,
        onOpenTask: (_) => openCount++,
        onAddToList: () => addCount++,
        onRegenerate: () => regenerateCount++,
        onClose: () => closeCount++,
      );

      expect(openCount, 0);
      expect(addCount, 0);
      expect(find.text('この育成を開く'), findsOneWidget);
      expect(find.text('今日のリストに追加'), findsOneWidget);
      expect(find.text('別の候補を見る'), findsOneWidget);
      expect(find.text('再生成'), findsOneWidget);
      expect(find.text('提案を閉じる'), findsOneWidget);

      await tester.tap(find.byKey(const Key('daily-plan-open-primary')));
      await tester.tap(find.byKey(const Key('daily-plan-add-to-list')));
      await tester.ensureVisible(find.text('再生成'));
      await tester.tap(find.text('再生成'));
      await tester.tap(find.text('提案を閉じる'));

      expect(openCount, 1);
      expect(addCount, 1);
      expect(regenerateCount, 1);
      expect(closeCount, 1);
    });
  });

  testWidgets('task details never expose internal character or material IDs', (
    tester,
  ) async {
    const internalCharacterId = '10000046';
    const internalMaterialId = '104319';
    const item = DailyPlanItem(
      id: 'internal_task_id',
      type: DailyPlanItemType.talent,
      title: '天賦素材を集める',
      characterIds: [internalCharacterId],
      materialIds: [internalMaterialId],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyPlanTaskTile(
            item: item,
            completed: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('なぜ必要？ / 何が足りない？'));
    await tester.pumpAndSettle();

    expect(find.textContaining(internalCharacterId), findsNothing);
    expect(find.textContaining(internalMaterialId), findsNothing);
    expect(find.textContaining('名称を確認中'), findsNWidgets(2));
  });

  testWidgets('AI generation does not save; add-to-list is the save boundary', (
    tester,
  ) async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final store = DailyPlanProposalStore(db);
    final item = _item(0);
    final plan = DailyPlan(
      userId: 'proposal-save-test-user',
      date: DateTime(2026, 8, 4),
      items: [item],
      availableMinutes: 30,
    );
    final proposal = _proposal([
      item,
    ], proposalFingerprint: dailyPlanFingerprint(plan));

    Future<DailyPlanProposal?> savedProposal() => store.read(
      userScope: dailyPlanSafeUserScope(plan.userId),
      localDate: formatLocalDate(plan.date),
      planFingerprint: dailyPlanFingerprint(plan),
      plan: plan,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyPlanProvider.overrideWith((ref) async => plan),
          adoptedDailyPlanProvider.overrideWith((ref) async => plan),
          dailyPlanProposalProvider(0).overrideWith((ref) async => proposal),
          dailyPlanProposalStoreProvider.overrideWith((ref) async => store),
          dailyPlanTodayCompletionsProvider.overrideWith(
            (ref) async => <String>{},
          ),
          charactersProvider.overrideWith((ref) async => <MasterCharacter>[]),
          materialsMapProvider.overrideWith(
            (ref) async => <String, MasterMaterial>{},
          ),
        ],
        child: const MaterialApp(home: DailyPlanScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(await savedProposal(), isNull);

    await tester.tap(find.byKey(const Key('daily-plan-add-to-list')));
    await tester.pumpAndSettle();

    expect(await savedProposal(), isNotNull);
    expect(find.text('追加済み'), findsOneWidget);
  });

  testWidgets('stale proposal is rejected and regenerated without saving', (
    tester,
  ) async {
    final db = await AppDatabase.openInMemory();
    addTearDown(db.close);
    final store = DailyPlanProposalStore(db);
    final currentPlan = DailyPlan(
      userId: 'proposal-stale-test-user',
      date: DateTime(2026, 8, 4),
      items: [_item(0, title: '更新後の育成タスク')],
      availableMinutes: 30,
    );
    final stalePlan = currentPlan.copyWith(
      items: [currentPlan.items.single.copyWith(priority: 999)],
    );
    final staleProposal = _proposal(
      stalePlan.items,
      proposalFingerprint: dailyPlanFingerprint(stalePlan),
    );

    expect(canAdoptDailyPlanProposal(currentPlan, staleProposal), isFalse);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyPlanProvider.overrideWith((ref) async => currentPlan),
          adoptedDailyPlanProvider.overrideWith((ref) async => currentPlan),
          dailyPlanProposalProvider(
            0,
          ).overrideWith((ref) async => staleProposal),
          dailyPlanProposalProvider(1).overrideWith(
            (ref) async => buildDeterministicDailyPlanProposal(currentPlan),
          ),
          dailyPlanProposalStoreProvider.overrideWith((ref) async => store),
          dailyPlanTodayCompletionsProvider.overrideWith(
            (ref) async => <String>{},
          ),
          charactersProvider.overrideWith((ref) async => <MasterCharacter>[]),
          materialsMapProvider.overrideWith(
            (ref) async => <String, MasterMaterial>{},
          ),
        ],
        child: const MaterialApp(home: DailyPlanScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('daily-plan-add-to-list')));
    await tester.pumpAndSettle();

    expect(find.text('提案が古くなったため、再生成します'), findsOneWidget);
    expect(
      await store.read(
        userScope: dailyPlanSafeUserScope(currentPlan.userId),
        localDate: formatLocalDate(currentPlan.date),
        planFingerprint: dailyPlanFingerprint(currentPlan),
        plan: currentPlan,
      ),
      isNull,
    );
  });
}

DailyPlanItem _item(
  int index, {
  String? title,
  bool availableToday = true,
  int estimatedMinutes = 10,
  List<MissingData> missingData = const [],
  List<String> reasons = const ['今日開放', '期限が近い'],
}) {
  return DailyPlanItem(
    id: 'task_$index',
    type: index.isEven ? DailyPlanItemType.talent : DailyPlanItemType.weapon,
    title: title ?? '育成タスク $index',
    description: '目標に必要な育成です',
    priority: 100 - index,
    estimatedResinCost: 20 + index,
    estimatedMinutes: estimatedMinutes,
    currentLevel: 7,
    targetLevel: 9,
    availableToday: availableToday,
    requiresResin: true,
    bookmarked: true,
    reasons: reasons,
    missingData: missingData,
  );
}

DailyPlanProposal _proposal(
  List<DailyPlanItem> items, {
  String summary = '今日の育成候補を整理しました',
  String reason = '今日進める効果が大きいため',
  List<String> deferredTaskIds = const [],
  DailyPlanRecommendationSource source = DailyPlanRecommendationSource.deepseek,
  String proposalFingerprint =
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
}) {
  return DailyPlanProposal(
    summary: summary,
    recommendations: [
      for (var index = 0; index < items.length; index++)
        DailyPlanRecommendation(
          taskId: items[index].id,
          priority: index + 1,
          reason: reason,
          suggestedMinutes: 10 + index,
        ),
    ],
    deferredTaskIds: deferredTaskIds,
    warnings: const [],
    source: source,
    generatedAt: DateTime.utc(2026, 8, 4, 3, 5),
    inputHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    proposalFingerprint: proposalFingerprint,
  );
}

Finder _findKeyPrefix(String prefix) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required DailyPlanProposal proposal,
  required List<DailyPlanItem> items,
  int? availableMinutes,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Size viewport = const Size(390, 844),
  ValueChanged<DailyPlanItem>? onOpenTask,
  VoidCallback? onAddToList,
  VoidCallback? onRegenerate,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, colorSchemeSeed: Colors.teal),
      home: MediaQuery(
        data: MediaQueryData(
          size: viewport,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyPlanProposalPanel(
              proposal: proposal,
              items: items,
              availableMinutes: availableMinutes,
              onOpenTask: onOpenTask ?? (_) {},
              onAddToList: onAddToList ?? () {},
              onRegenerate: onRegenerate ?? () {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
