import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/planning/build_growth_route_request.dart';
import '../../../domain/planning/daily_plan.dart';
import '../../../domain/planning/daily_plan_completion_record.dart';
import '../../../domain/planning/daily_plan_item_key.dart';
import '../../../domain/recommendation/recommendation.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/daily_plan_completion_providers.dart';
import '../../../providers/growth_providers.dart';

/// Daily plan detail screen — shows all recommended tasks with completion toggles.
class DailyPlanScreen extends ConsumerStatefulWidget {
  const DailyPlanScreen({super.key});

  @override
  ConsumerState<DailyPlanScreen> createState() => _DailyPlanScreenState();
}

class _DailyPlanScreenState extends ConsumerState<DailyPlanScreen> {
  Set<String>? _optimisticCompleted;
  final Set<String> _busyKeys = {};

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('完了状態の保存に失敗しました')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyKeys.remove(itemKey));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(dailyPlanProvider);
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
                  '育成目標を設定すると、今日おすすめの育成項目が表示されます。',
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: plan.items.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == plan.items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/growth-route', extra: routeReq),
                          icon: const Icon(Icons.route),
                          label: const Text('育成ルートを作成'),
                        ),
                      );
                    }
                    final item = plan.items[i];
                    final key = dailyPlanItemKey(item);
                    final isDone = completed.contains(key);
                    return Card(
                      child: CheckboxListTile(
                        value: isDone,
                        onChanged: _busyKeys.contains(key)
                            ? null
                            : (v) => _toggleItem(
                                  item: item,
                                  complete: v ?? false,
                                  baseline: baseline,
                                ),
                        title: Text(
                          item.title,
                          style: isDone
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.disabledColor,
                                )
                              : null,
                        ),
                        subtitle: Text('優先度: ${item.priority}'),
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
