import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/build_recommendations/build_recommendation.dart';
import '../../../providers/build_recommendation_providers.dart';

/// ヘッダー右側の育成優先度（YouTube 由来）。タップで根拠を表示。
class InvestmentPriorityBadge extends ConsumerWidget {
  const InvestmentPriorityBadge({
    super.key,
    required this.characterId,
  });

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(buildRecommendationProvider(characterId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) {
        if (error is BuildRecommendationException &&
            (error.failure == BuildRecommendationFailure.notConfigured ||
                error.failure == BuildRecommendationFailure.notFound)) {
          return const _Badge(
            priority: InvestmentPriority.none,
            onTap: null,
          );
        }
        return const _Badge(
          priority: InvestmentPriority.none,
          onTap: null,
        );
      },
      data: (recommendation) {
        if (recommendation == null) {
          return const _Badge(
            priority: InvestmentPriority.none,
            onTap: null,
          );
        }
        return _Badge(
          priority: recommendation.investmentPriority,
          onTap: recommendation.investmentPriority == InvestmentPriority.none
              ? null
              : () => _showDetails(context, recommendation),
        );
      },
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    CharacterBuildRecommendation recommendation,
  ) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.investmentPriority.fullLabel,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '攻略動画から整理した育成優先度の目安です。公式の優先度ではありません。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (recommendation.role != null &&
                    recommendation.role!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('役割: ${recommendation.role}', style: theme.textTheme.bodyMedium),
                ],
                if (recommendation.teamArchetype != null &&
                    recommendation.teamArchetype!.trim().isNotEmpty)
                  Text(
                    '編成: ${recommendation.teamArchetype}',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (recommendation.freshnessCaption != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    recommendation.freshnessCaption!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (recommendation.notes != null &&
                    recommendation.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(recommendation.notes!, style: theme.textTheme.bodyMedium),
                ],
                if (recommendation.sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('出典（攻略動画）', style: theme.textTheme.labelMedium),
                  ...recommendation.sources.take(3).map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${s.channelTitle} · ${s.title}',
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.priority,
    required this.onTap,
  });

  final InvestmentPriority priority;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = switch (priority) {
      InvestmentPriority.high => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      InvestmentPriority.medium => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      InvestmentPriority.low => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      InvestmentPriority.none => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '育成優先度',
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.85),
            ),
          ),
          Text(
            priority.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    if (onTap == null || priority == InvestmentPriority.none) {
      return Semantics(
        label: priority.fullLabel,
        child: child,
      );
    }

    return Semantics(
      button: true,
      label: '${priority.fullLabel}。詳細を開く',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}
