import 'package:flutter/material.dart';

import '../../../domain/build_recommendations/guide_insight.dart';

/// Akasha / YouTube の出典を色以外でも区別するラベル。
class GuideSourceLabel extends StatelessWidget {
  const GuideSourceLabel({
    super.key,
    required this.source,
    this.compact = false,
  });

  final GuideInsightSource source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = switch (source) {
      GuideInsightSource.akasha => ('Akasha · 使用率', Icons.bar_chart_outlined),
      GuideInsightSource.youtube => (
        '攻略動画 · おすすめ',
        Icons.ondemand_video_outlined,
      ),
    };
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 14 : 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
