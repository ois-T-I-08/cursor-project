import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/daily_plan/daily_plan_proposal_store.dart';
import 'package:genshin_builder_mobile/data/db/app_database_facade.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_proposal.dart';

void main() {
  late AppDatabase db;
  late DailyPlanProposalStore store;

  const scope = '0123456789ab';
  const localDate = '2026-08-02';
  const fingerprint =
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
  final plan = DailyPlan(
    userId: 'raw-user-id',
    date: DateTime(2026, 8, 2),
    items: const [
      DailyPlanItem(
        id: 'task_a',
        type: DailyPlanItemType.growthGoal,
        title: '育成目標',
      ),
    ],
  );
  final proposal = DailyPlanProposal(
    summary: '今日の候補です',
    recommendations: const [
      DailyPlanRecommendation(
        taskId: 'task_a',
        priority: 1,
        reason: '既存の優先度が高いため',
        suggestedMinutes: 20,
      ),
    ],
    deferredTaskIds: const [],
    warnings: const [],
    source: DailyPlanRecommendationSource.deepseek,
    generatedAt: DateTime.utc(2026, 8, 2, 3),
    inputHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    proposalFingerprint: fingerprint,
    modelIdentifier: 'deepseek-v4-flash',
  );

  setUp(() async {
    db = await AppDatabase.openInMemory();
    store = DailyPlanProposalStore(db);
  });

  tearDown(() async => db.close());

  test(
    'persists only a validated final proposal for the matching fingerprint',
    () async {
      await store.save(
        userScope: scope,
        localDate: localDate,
        planFingerprint: fingerprint,
        proposal: proposal,
      );

      final loaded = await store.read(
        userScope: scope,
        localDate: localDate,
        planFingerprint: fingerprint,
        plan: plan,
      );
      expect(loaded?.recommendations.single.taskId, 'task_a');

      final raw = await db.getSetting(
        'daily_plan_adopted_v1_${scope}_$localDate',
      );
      expect(raw, isNot(contains(plan.userId)));
      expect(raw?.toLowerCase(), isNot(contains('prompt')));
      expect(raw?.toLowerCase(), isNot(contains('rawai')));

      expect(
        await store.read(
          userScope: scope,
          localDate: localDate,
          planFingerprint:
              '0000000000000000000000000000000000000000000000000000000000000000',
          plan: plan,
        ),
        isNull,
      );
    },
  );

  test('refuses to save a stale proposal under a new fingerprint', () async {
    expect(
      () => store.save(
        userScope: scope,
        localDate: localDate,
        planFingerprint:
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        proposal: proposal,
      ),
      throwsArgumentError,
    );
  });
}
