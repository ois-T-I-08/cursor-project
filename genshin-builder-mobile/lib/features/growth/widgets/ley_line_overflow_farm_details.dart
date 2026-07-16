import 'package:flutter/material.dart';

import '../../../domain/planning/ley_line_overflow.dart';

/// 地脈の奔流の開催ラベル（色に依存しない文字表示）。
String leyLineOverflowActiveLabel(String eventDisplayName) =>
    '$eventDisplayName 開催中';

/// 経験値本・モラカード内の奔流詳細（テーマ色でアクセント）。
class LeyLineOverflowFarmDetails extends StatelessWidget {
  const LeyLineOverflowFarmDetails({
    super.key,
    required this.overflow,
  });

  final LeyLineOverflowBreakdown overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eventAccent = scheme.tertiary;
    final runsStyle = theme.textTheme.bodySmall?.copyWith(
      color: eventAccent,
      fontWeight: FontWeight.w600,
    );
    final label = leyLineOverflowActiveLabel(overflow.eventDisplayName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.celebration_outlined,
                  size: 16,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '不足量：通常換算 約${overflow.normalEquivalentRuns}回分',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          '通常報酬換算：約${overflow.normalEquivalentRuns}回分',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          overflow.isMaxEstimate
              ? 'ボーナス適用回数：最大${overflow.bonusRunsApplied}回'
              : '本日のボーナス残り：${overflow.remainingBonusCapacity}回'
                  '（適用 ${overflow.bonusRunsApplied}回）',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          '実際の周回数：約${overflow.actualRuns}回',
          style: runsStyle,
        ),
        Text(
          '必要樹脂：約${overflow.resinTotal}',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          '計算根拠：ボーナス ${overflow.bonusRunsApplied}回'
          '×${overflow.rewardMultiplier}倍で'
          '通常換算 ${overflow.bonusRunsApplied * overflow.rewardMultiplier}回分を賄い、'
          '残り通常周回 ${overflow.normalRunsAfterBonus}回。',
          style: theme.textTheme.labelSmall,
        ),
        if (overflow.isMaxEstimate)
          Text(
            '本日の使用済み回数を取得できないため、'
            'ボーナスを最大回数利用した場合の目安です。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
