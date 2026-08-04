import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/daily_plan_notifications/daily_plan_user_scope.dart';
import '../../../application/planning/build_deterministic_daily_plan_proposal.dart';
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
import 'widgets/daily_plan_proposal_panel.dart';
import 'widgets/daily_plan_task_tile.dart';

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
        ).showSnackBar(const SnackBar(content: Text('今日のリストに追加しました')));
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

  void _openTask(DailyPlanItem item, Object routeRequest) {
    if (item.characterIds.isNotEmpty) {
      final characterId = Uri.encodeComponent(item.characterIds.first);
      context.push('/characters/$characterId');
      return;
    }
    context.push('/growth-route', extra: routeRequest);
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(adoptedDailyPlanProvider);
    final proposalAsync = ref.watch(
      dailyPlanProposalProvider(_proposalGeneration),
    );
    final completionsAsync = ref.watch(dailyPlanTodayCompletionsProvider);
    final materialsById =
        ref.watch(materialsMapProvider).valueOrNull ?? const {};
    final characters = ref.watch(charactersProvider).valueOrNull ?? const [];
    final charactersById = {
      for (final character in characters) character.id: character,
    };
    final characterNamesById = {
      for (final character in characters) character.id: character.name,
    };
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.task_alt,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '今日は優先する育成がありません',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '育成目標やブックマークを追加すると提案できます',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final baseline = completionsAsync.valueOrNull ?? const <String>{};
          final completed = _optimisticCompleted ?? baseline;
          final routeReq = buildGrowthRouteRequest(plan, today);
          final doneCount =
              plan.items
                  .where((item) => completed.contains(dailyPlanItemKey(item)))
                  .length;
          final fallbackProposal = buildDeterministicDailyPlanProposal(plan);

          DailyPlanProposalPanel proposalPanel(DailyPlanProposal proposal) {
            return DailyPlanProposalPanel(
              proposal: proposal,
              items: plan.items,
              charactersById: charactersById,
              materialsById: materialsById,
              currentResin: plan.currentResin,
              availableMinutes: plan.availableMinutes,
              adding: _adopting,
              added: _adoptedInputHash == proposal.inputHash,
              onOpenTask: (item) => _openTask(item, routeReq),
              onAddToList: () => _adoptProposal(proposal),
              onRegenerate: _regenerateProposal,
              onClose: () => setState(() => _proposalClosed = true),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!_proposalClosed) ...[
                proposalAsync.when(
                  loading: () => proposalPanel(fallbackProposal),
                  error: (_, __) => proposalPanel(fallbackProposal),
                  data: proposalPanel,
                ),
                const SizedBox(height: 16),
              ],
              _PlanStatusHeader(
                plan: plan,
                doneCount: doneCount,
                totalCount: plan.items.length,
              ),
              const SizedBox(height: 16),
              Text('やること一覧', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'チップで「何が必要か」を確認。詳しく見るで理由と素材名を開けます。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final item in plan.items) ...[
                DailyPlanTaskTile(
                  item: item,
                  completed: completed.contains(dailyPlanItemKey(item)),
                  enabled: !_busyKeys.contains(dailyPlanItemKey(item)),
                  materialsById: materialsById,
                  characterNamesById: characterNamesById,
                  onChanged:
                      (value) => _toggleItem(
                        item: item,
                        complete: value ?? false,
                        baseline: baseline,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => context.push('/growth-route', extra: routeReq),
                icon: const Icon(Icons.route),
                label: const Text('育成ルートを作成'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanStatusHeader extends StatelessWidget {
  const _PlanStatusHeader({
    required this.plan,
    required this.doneCount,
    required this.totalCount,
  });

  final DailyPlan plan;
  final int doneCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resinText =
        plan.currentResin == null
            ? '樹脂 未取得'
            : plan.maxResin == null
            ? '樹脂 ${plan.currentResin}'
            : '樹脂 ${plan.currentResin} / ${plan.maxResin}';
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今日の進捗 $doneCount / $totalCount',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  resinText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            if (plan.missingData.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'データ不足: ${_missingDataLabel(plan)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _missingDataLabel(DailyPlan plan) {
    final labels = <String>[];
    for (final missing in plan.missingData) {
      switch (missing) {
        case MissingData.materialInventory:
          labels.add('素材所持');
        case MissingData.currentResin:
          labels.add('樹脂');
        case MissingData.masterUpgradeData:
          labels.add('育成マスタ');
        case MissingData.unequippedWeapons:
          labels.add('未装備武器');
        case MissingData.currentAbyssEnemies:
          labels.add('螺旋敵情報');
        case MissingData.currentTheaterRules:
          labels.add('シアター条件');
        case MissingData.teamUsageStatistics:
          labels.add('編成統計');
      }
    }
    return labels.isEmpty ? '一部不明' : labels.join('、');
  }
}
