import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/daily_plan_notifications/daily_plan_user_scope.dart';
import '../../../application/planning/build_growth_route_request.dart';
import '../../../application/planning/daily_plan_fingerprint.dart';
import '../../../domain/planning/daily_plan.dart';
import '../../../domain/planning/daily_plan_completion_record.dart';
import '../../../domain/planning/daily_plan_item_key.dart';
import '../../../domain/planning/daily_plan_proposal.dart';
import '../../../domain/recommendation/recommendation.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/daily_plan_completion_providers.dart';
import '../../../providers/growth_providers.dart';

/// Existing daily-plan screen with an optional, explicitly adopted proposal.
class DailyPlanScreen extends ConsumerStatefulWidget {
  const DailyPlanScreen({super.key});

  @override
  ConsumerState<DailyPlanScreen> createState() => _DailyPlanScreenState();
}

class _DailyPlanScreenState extends ConsumerState<DailyPlanScreen> {
  Set<String>? _optimisticCompleted;
  final Set<String> _busyKeys = {};
  int _proposalGeneration = 0;
  bool _proposalClosed = false;
  bool _adopting = false;
  String? _adoptedInputHash;

  Future<void> _toggleItem({
    required DailyPlanItem item,
    required bool complete,
    required Set<String> baseline,
  }) async {
    final itemKey = dailyPlanItemKey(item);
    if (_busyKeys.contains(itemKey)) return;

    final previous = Set<String>.from(_optimisticCompleted ?? baseline);
    final next = Set<String>.from(previous);
    if (complete) {
      next.add(itemKey);
    } else {
      next.remove(itemKey);
    }

    setState(() {
      _optimisticCompleted = next;
      _busyKeys.add(itemKey);
    });

    try {
      final repo = await ref.read(dailyPlanCompletionRepoProvider.future);
      final userId = await ref.read(localUserIdProvider.future);
      final localDate = formatLocalDate(DateTime.now());
      if (complete) {
        await repo.markCompleted(
          DailyPlanCompletionRecord(
            userId: userId,
            localDate: localDate,
            itemKey: itemKey,
            completedAt: DateTime.now(),
          ),
        );
      } else {
        await repo.unmarkCompleted(
          userId: userId,
          localDate: localDate,
          itemKey: itemKey,
        );
      }
      ref.invalidate(dailyPlanTodayCompletionsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _optimisticCompleted = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('完了状態の保存に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _busyKeys.remove(itemKey));
    }
  }

  Future<void> _adoptProposal(DailyPlanProposal proposal) async {
    if (_adopting) return;
    setState(() => _adopting = true);
    try {
      final plan = await ref.read(dailyPlanProvider.future);
      final store = await ref.read(dailyPlanProposalStoreProvider.future);
      await store.save(
        userScope: dailyPlanSafeUserScope(plan.userId),
        localDate: formatLocalDate(plan.date),
        planFingerprint: dailyPlanFingerprint(plan),
        proposal: proposal,
      );
      ref.invalidate(adoptedDailyPlanProvider);
      if (mounted) {
        setState(() => _adoptedInputHash = proposal.inputHash);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('今日の提案を採用しました')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提案の保存に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _adopting = false);
    }
  }

  void _regenerateProposal() {
    setState(() {
      _proposalClosed = false;
      _proposalGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(adoptedDailyPlanProvider);
    final proposalAsync = ref.watch(
      dailyPlanProposalProvider(_proposalGeneration),
    );
    final completionsAsync = ref.watch(dailyPlanTodayCompletionsProvider);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(title: const Text('今日やること')),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('読み込みエラー')),
        data: (plan) {
          if (plan.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '育成目標の設定、または今日開放の曜日素材の不足があると、おすすめが表示されます。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            );
          }

          final baseline = completionsAsync.valueOrNull ?? const <String>{};
          final completed = _optimisticCompleted ?? baseline;
          final routeReq = buildGrowthRouteRequest(plan, today);

          return Column(
            children: [
              if (!_proposalClosed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: proposalAsync.when(
                    loading:
                        () => const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('今日のおすすめを考えています…'),
                              ],
                            ),
                          ),
                        ),
                    error:
                        (_, __) => _ProposalUnavailableCard(
                          onRetry: _regenerateProposal,
                          onClose: () => setState(() => _proposalClosed = true),
                        ),
                    data:
                        (proposal) => _DailyPlanProposalCard(
                          proposal: proposal,
                          items: plan.items,
                          adopting: _adopting,
                          adopted: _adoptedInputHash == proposal.inputHash,
                          onRegenerate: _regenerateProposal,
                          onAdopt: () => _adoptProposal(proposal),
                          onClose: () => setState(() => _proposalClosed = true),
                        ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: plan.items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == plan.items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: OutlinedButton.icon(
                          onPressed:
                              () => context.push(
                                '/growth-route',
                                extra: routeReq,
                              ),
                          icon: const Icon(Icons.route),
                          label: const Text('育成ルートを作成'),
                        ),
                      );
                    }
                    final item = plan.items[index];
                    final key = dailyPlanItemKey(item);
                    final isDone = completed.contains(key);
                    final subtitle = <String>[
                      '優先度: ${item.priority}',
                      if (item.reasons.isNotEmpty) item.reasons.first,
                      if (!item.availableToday) '本日は対象素材を入手できません',
                    ].join(' · ');
                    return Card(
                      child: CheckboxListTile(
                        value: isDone,
                        onChanged:
                            _busyKeys.contains(key)
                                ? null
                                : (value) => _toggleItem(
                                  item: item,
                                  complete: value ?? false,
                                  baseline: baseline,
                                ),
                        title: Text(
                          item.title,
                          style:
                              isDone
                                  ? TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: theme.disabledColor,
                                  )
                                  : null,
                        ),
                        subtitle: Text(subtitle),
                        secondary:
                            item.confidence == RecommendationConfidence.high
                                ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                                : const Icon(Icons.info_outline),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DailyPlanProposalCard extends StatelessWidget {
  const _DailyPlanProposalCard({
    required this.proposal,
    required this.items,
    required this.adopting,
    required this.adopted,
    required this.onRegenerate,
    required this.onAdopt,
    required this.onClose,
  });

  final DailyPlanProposal proposal;
  final List<DailyPlanItem> items;
  final bool adopting;
  final bool adopted;
  final VoidCallback onRegenerate;
  final VoidCallback onAdopt;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemById = {for (final item in items) item.id: item};
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  proposal.isAiGenerated ? Icons.auto_awesome : Icons.rule,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今日のおすすめ · ${proposal.sourceLabel}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '提案を閉じる',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(proposal.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final recommendation in proposal.recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      child: Text('${recommendation.priority}'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemById[recommendation.taskId]?.title ??
                                recommendation.taskId,
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            '${recommendation.reason} · 約${recommendation.suggestedMinutes}分',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (proposal.warnings.isNotEmpty)
              Text(
                proposal.warnings.first,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: adopting || adopted ? null : onAdopt,
                  icon: Icon(adopted ? Icons.check : Icons.playlist_add_check),
                  label: Text(adopted ? '採用済み' : '提案を採用'),
                ),
                OutlinedButton.icon(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再生成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProposalUnavailableCard extends StatelessWidget {
  const _ProposalUnavailableCard({
    required this.onRetry,
    required this.onClose,
  });

  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('おすすめを読み込めませんでした'),
        subtitle: const Text('通常の今日やることはそのまま利用できます。'),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: '再試行',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '閉じる',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
