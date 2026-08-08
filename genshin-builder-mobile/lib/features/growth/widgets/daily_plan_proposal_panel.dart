import 'package:flutter/material.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/planning/daily_plan.dart';
import '../../../domain/planning/daily_plan_proposal.dart';
import '../../shared/game_icon_image.dart';
import 'daily_plan_item_labels.dart';

/// Three-second hierarchy for a validated daily-plan proposal.
///
/// Only structured local facts are shown before expansion. AI free text and
/// source metadata remain inside the explanation section.
class DailyPlanProposalPanel extends StatefulWidget {
  const DailyPlanProposalPanel({
    super.key,
    required this.proposal,
    required this.items,
    required this.onOpenTask,
    required this.onAddToList,
    required this.onRegenerate,
    required this.onClose,
    this.charactersById = const {},
    this.materialsById = const {},
    this.currentResin,
    this.availableMinutes,
    this.adding = false,
    this.added = false,
  });

  final DailyPlanProposal proposal;
  final List<DailyPlanItem> items;
  final Map<String, MasterCharacter> charactersById;
  final Map<String, MasterMaterial> materialsById;
  final int? currentResin;
  final int? availableMinutes;
  final bool adding;
  final bool added;
  final ValueChanged<DailyPlanItem> onOpenTask;
  final VoidCallback onAddToList;
  final VoidCallback onRegenerate;
  final VoidCallback onClose;

  @override
  State<DailyPlanProposalPanel> createState() => _DailyPlanProposalPanelState();
}

class _DailyPlanProposalPanelState extends State<DailyPlanProposalPanel> {
  final _alternativesKey = GlobalKey();
  bool _showAllRecommendations = false;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveRecommendations();
    if (resolved.isEmpty) return const _NoPriorityTasksCard();

    final primary = resolved.first;
    final next = resolved.skip(1).take(2).toList(growable: false);
    final extra = resolved.skip(3).toList(growable: false);
    final deferred = _resolveDeferred(resolved);
    final statusText =
        widget.proposal.isAiGenerated ? 'AIが今日の候補を整理しました' : '期限と育成効率から提案しています';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(
                widget.proposal.isAiGenerated
                    ? Icons.auto_awesome
                    : Icons.rule_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _PrimaryTaskCard(
          key: const Key('daily-plan-primary-card'),
          task: primary,
          charactersById: widget.charactersById,
          materialsById: widget.materialsById,
          adding: widget.adding,
          added: widget.added,
          hasAlternatives: resolved.length > 1,
          onOpen: () => widget.onOpenTask(primary.item),
          onAddToList: widget.onAddToList,
          onShowAlternatives: _showAlternatives,
        ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '次にやること',
            key: _alternativesKey,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final task in next)
            _NextTaskRow(
              key: ValueKey('daily-plan-next-task-${task.item.id}'),
              task: task,
              charactersById: widget.charactersById,
              materialsById: widget.materialsById,
              onTap: () => widget.onOpenTask(task.item),
            ),
          if (extra.isNotEmpty) ...[
            if (_showAllRecommendations)
              for (final task in extra)
                _NextTaskRow(
                  key: ValueKey('daily-plan-extra-task-${task.item.id}'),
                  task: task,
                  charactersById: widget.charactersById,
                  materialsById: widget.materialsById,
                  onTap: () => widget.onOpenTask(task.item),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('daily-plan-more-recommendations'),
                onPressed:
                    () => setState(
                      () => _showAllRecommendations = !_showAllRecommendations,
                    ),
                icon: Icon(
                  _showAllRecommendations
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                label: Text(
                  _showAllRecommendations ? '候補を閉じる' : 'ほか${extra.length}件を見る',
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 8),
        _ProposalExplanation(proposal: widget.proposal, tasks: resolved),
        if (deferred.isNotEmpty)
          _DeferredTasks(
            items: deferred,
            currentResin: widget.currentResin,
            availableMinutes: widget.availableMinutes,
          ),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            TextButton.icon(
              onPressed: widget.onRegenerate,
              icon: const Icon(Icons.refresh),
              label: const Text('再生成'),
            ),
            TextButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              label: const Text('提案を閉じる'),
            ),
          ],
        ),
      ],
    );
  }

  List<_ResolvedRecommendation> _resolveRecommendations() {
    final byId = {for (final item in widget.items) item.id: item};
    final recommendations = [...widget.proposal.recommendations]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final seen = <String>{};
    final resolved = <_ResolvedRecommendation>[];
    for (final recommendation in recommendations) {
      final item = byId[recommendation.taskId];
      if (item == null || !item.availableToday || !seen.add(item.id)) continue;
      resolved.add(
        _ResolvedRecommendation(
          recommendation: recommendation,
          item: item,
          displayRank: resolved.length + 1,
        ),
      );
    }
    return resolved;
  }

  List<DailyPlanItem> _resolveDeferred(List<_ResolvedRecommendation> resolved) {
    final selected = {for (final task in resolved) task.item.id};
    final deferredIds = widget.proposal.deferredTaskIds.toSet();
    return [
      for (final item in widget.items)
        if (!selected.contains(item.id) &&
            (deferredIds.contains(item.id) || !item.availableToday))
          item,
    ];
  }

  void _showAlternatives() {
    if (!_showAllRecommendations) {
      setState(() => _showAllRecommendations = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _alternativesKey.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(targetContext, duration: Duration.zero);
      }
    });
  }
}

class _PrimaryTaskCard extends StatelessWidget {
  const _PrimaryTaskCard({
    super.key,
    required this.task,
    required this.charactersById,
    required this.materialsById,
    required this.adding,
    required this.added,
    required this.hasAlternatives,
    required this.onOpen,
    required this.onAddToList,
    required this.onShowAlternatives,
  });

  final _ResolvedRecommendation task;
  final Map<String, MasterCharacter> charactersById;
  final Map<String, MasterMaterial> materialsById;
  final bool adding;
  final bool added;
  final bool hasAlternatives;
  final VoidCallback onOpen;
  final VoidCallback onAddToList;
  final VoidCallback onShowAlternatives;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badges = dailyPlanReasonBadges(task.item);
    final goal = dailyPlanGoalLabel(task.item);

    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日の最優先',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TaskIcon(
                  item: task.item,
                  charactersById: charactersById,
                  materialsById: materialsById,
                  size: 56,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.item.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dailyPlanPrimaryReason(task.item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final badge in badges)
                    _ReasonBadge(
                      key: ValueKey(
                        'daily-plan-reason-badge-${task.item.id}-$badge',
                      ),
                      label: badge,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (goal != null) ...[
              Text(
                goal,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              dailyPlanEstimateLabel(
                task.item,
                suggestedMinutes: task.recommendation.suggestedMinutes,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('daily-plan-open-primary'),
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('この育成を開く'),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  key: const Key('daily-plan-add-to-list'),
                  onPressed: adding || added ? null : onAddToList,
                  icon: Icon(added ? Icons.check : Icons.playlist_add_outlined),
                  label: Text(added ? '追加済み' : '今日のリストに追加'),
                ),
                if (hasAlternatives)
                  TextButton.icon(
                    key: const Key('daily-plan-show-alternatives'),
                    onPressed: onShowAlternatives,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('別の候補を見る'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NextTaskRow extends StatelessWidget {
  const _NextTaskRow({
    super.key,
    required this.task,
    required this.charactersById,
    required this.materialsById,
    required this.onTap,
  });

  final _ResolvedRecommendation task;
  final Map<String, MasterCharacter> charactersById;
  final Map<String, MasterMaterial> materialsById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${task.displayRank}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TaskIcon(
                item: task.item,
                charactersById: charactersById,
                materialsById: materialsById,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dailyPlanNextTaskMeta(
                        task.item,
                        suggestedMinutes: task.recommendation.suggestedMinutes,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, semanticLabel: '詳細を開く'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProposalExplanation extends StatelessWidget {
  const _ProposalExplanation({required this.proposal, required this.tasks});

  final DailyPlanProposal proposal;
  final List<_ResolvedRecommendation> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: const Key('daily-plan-ai-explanation'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: const Text('AIがこの順番にした理由'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(proposal.summary, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 12),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${task.displayRank}.', style: theme.textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.item.title, style: theme.textTheme.labelLarge),
                      Text(
                        task.recommendation.reason,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (proposal.warnings.isNotEmpty) ...[
          const Divider(),
          for (final warning in proposal.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('注意: $warning', style: theme.textTheme.bodySmall),
            ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '提案方法: ${proposal.isAiGenerated ? 'AI提案' : '通常ルール提案'}\n'
            '生成時刻: ${_formatGeneratedAt(proposal.generatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeferredTasks extends StatelessWidget {
  const _DeferredTasks({
    required this.items,
    required this.currentResin,
    required this.availableMinutes,
  });

  final List<DailyPlanItem> items;
  final int? currentResin;
  final int? availableMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: const Key('daily-plan-deferred-tasks'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: const Text('今日は見送る項目'),
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.labelLarge),
                      Text(
                        dailyPlanDeferredReason(
                          item,
                          currentResin: currentResin,
                          availableMinutes: availableMinutes,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TaskIcon extends StatelessWidget {
  const _TaskIcon({
    required this.item,
    required this.charactersById,
    required this.materialsById,
    required this.size,
  });

  final DailyPlanItem item;
  final Map<String, MasterCharacter> charactersById;
  final Map<String, MasterMaterial> materialsById;
  final double size;

  @override
  Widget build(BuildContext context) {
    String? iconUrl;
    if (item.characterIds.isNotEmpty) {
      iconUrl = charactersById[item.characterIds.first]?.iconUrl;
    }
    if ((iconUrl == null || iconUrl.isEmpty) && item.materialIds.isNotEmpty) {
      iconUrl = materialsById[item.materialIds.first]?.iconUrl;
    }
    return Semantics(
      label: '${dailyPlanItemTypeLabel(item.type)}のアイコン',
      image: true,
      child: GameIconImage(
        iconUrl: iconUrl,
        size: size,
        borderRadius: 12,
        fallback: Icon(dailyPlanItemTypeIcon(item.type), size: size * 0.55),
      ),
    );
  }
}

class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoPriorityTasksCard extends StatelessWidget {
  const _NoPriorityTasksCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('daily-plan-empty-proposal'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.task_alt, color: theme.colorScheme.primary, size: 28),
            const SizedBox(height: 10),
            Text('今日は優先する育成がありません', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '育成目標やブックマークを追加すると提案できます',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedRecommendation {
  const _ResolvedRecommendation({
    required this.recommendation,
    required this.item,
    required this.displayRank,
  });

  final DailyPlanRecommendation recommendation;
  final DailyPlanItem item;
  final int displayRank;
}

String _formatGeneratedAt(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day $hour:$minute';
}
