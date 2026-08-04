import 'package:flutter/material.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/planning/daily_plan.dart';
import 'daily_plan_item_labels.dart';

/// Intuitive task row: what / why / cost at a glance, details on expand.
class DailyPlanTaskTile extends StatelessWidget {
  const DailyPlanTaskTile({
    super.key,
    required this.item,
    required this.completed,
    required this.onChanged,
    this.materialsById = const {},
    this.characterNamesById = const {},
    this.enabled = true,
  });

  final DailyPlanItem item;
  final bool completed;
  final ValueChanged<bool?>? onChanged;
  final Map<String, MasterMaterial> materialsById;
  final Map<String, String> characterNamesById;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = dailyPlanItemTypeLabel(item.type);
    final levelLabel = dailyPlanLevelLabel(item);
    final materialNames = [
      for (final id in item.materialIds.take(4))
        if (materialsById[id]?.name case final name?) name,
    ];
    final characterNames = [
      for (final id in item.characterIds.take(4))
        if (characterNamesById[id] case final name?) name,
    ];
    final unknownMaterialCount = item.materialIds.length - materialNames.length;
    final unknownCharacterCount =
        item.characterIds.length - characterNames.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          CheckboxListTile(
            value: completed,
            onChanged: enabled ? onChanged : null,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
            title: Text(
              item.title,
              style:
                  completed
                      ? theme.textTheme.titleSmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.disabledColor,
                      )
                      : theme.textTheme.titleSmall,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _FactChip(
                    icon: dailyPlanItemTypeIcon(item.type),
                    label: typeLabel,
                  ),
                  if (levelLabel != null)
                    _FactChip(icon: Icons.stairs_outlined, label: levelLabel),
                  if (item.estimatedResinCost != null)
                    _FactChip(
                      icon: Icons.water_drop_outlined,
                      label: '樹脂 ${item.estimatedResinCost}',
                    ),
                  if (item.estimatedMinutes != null)
                    _FactChip(
                      icon: Icons.schedule,
                      label: '約${item.estimatedMinutes}分',
                    ),
                  _FactChip(
                    icon:
                        item.availableToday
                            ? Icons.check_circle_outline
                            : Icons.event_busy_outlined,
                    label: item.availableToday ? '今日できる' : '今日は不可',
                    tone:
                        item.availableToday
                            ? _ChipTone.positive
                            : _ChipTone.warning,
                  ),
                  if (item.bookmarked)
                    const _FactChip(
                      icon: Icons.bookmark_outline,
                      label: 'ブックマーク',
                    ),
                ],
              ),
            ),
          ),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Text('なぜ必要？ / 何が足りない？', style: theme.textTheme.labelLarge),
              children: [
                if (item.description != null && item.description!.isNotEmpty)
                  _DetailBlock(
                    label: 'いまの状況',
                    child: Text(
                      item.description!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (item.reasons.isNotEmpty)
                  _DetailBlock(
                    label: 'おすすめの理由',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final reason in item.reasons)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(reason),
                          ),
                      ],
                    ),
                  ),
                if (item.characterIds.isNotEmpty)
                  _DetailBlock(
                    label: '対象キャラ',
                    child: Text(
                      [
                        ...characterNames,
                        if (unknownCharacterCount > 0)
                          '名称を確認中 $unknownCharacterCount件',
                      ].join('、'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (item.materialIds.isNotEmpty)
                  _DetailBlock(
                    label: '必要な素材',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final name in materialNames)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (unknownMaterialCount > 0)
                          Text(
                            '名称を確認中の素材 $unknownMaterialCount種類',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (item.requiresResin && item.estimatedResinCost == null)
                  _DetailBlock(
                    label: '樹脂',
                    child: Text(
                      '樹脂が必要です（正確な消費量は未計算）',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChipTone { neutral, positive, warning }

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.icon,
    required this.label,
    this.tone = _ChipTone.neutral,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg;
    final Color fg;
    switch (tone) {
      case _ChipTone.positive:
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
      case _ChipTone.warning:
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
      case _ChipTone.neutral:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
