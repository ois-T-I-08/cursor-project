import 'package:flutter/material.dart';

import '../../../domain/build_recommendations/guide_insight.dart';
import '../../../domain/models/artifact_state.dart';
import 'guide_source_label.dart';

/// YouTube 由来の時計・杯・冠メインステータス推奨。
class GuideMainStatsPanel extends StatelessWidget {
  const GuideMainStatsPanel({
    super.key,
    required this.mainStats,
    this.freshnessCaption,
    this.compact = false,
    this.filterSlot,
  });

  final List<GuideMainStatRecommendation> mainStats;
  final String? freshnessCaption;
  final bool compact;

  /// 指定時はその部位のみ表示（聖遺物詳細シート向け）
  final GuideArtifactSlot? filterSlot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items =
        filterSlot == null
            ? mainStats
            : mainStats.where((e) => e.slot == filterSlot).toList();

    if (items.isEmpty) {
      return Text(
        'メインステータスのおすすめはまだ登録されていません。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final slots =
        filterSlot != null
            ? [filterSlot!]
            : const [
              GuideArtifactSlot.sands,
              GuideArtifactSlot.goblet,
              GuideArtifactSlot.circlet,
            ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text('おすすめメインステータス', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const GuideSourceLabel(source: GuideInsightSource.youtube),
          const SizedBox(height: 4),
          Text(
            '攻略動画から整理した目安です。公式推奨ではありません。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (freshnessCaption != null) ...[
            const SizedBox(height: 4),
            Text(
              freshnessCaption!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
        ...slots.map((slot) {
          final forSlot = items.where((e) => e.slot == slot).toList();
          if (forSlot.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SlotBlock(slot: slot, recommendations: forSlot),
          );
        }),
      ],
    );
  }
}

class _SlotBlock extends StatelessWidget {
  const _SlotBlock({required this.slot, required this.recommendations});

  final GuideArtifactSlot slot;
  final List<GuideMainStatRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...recommendations.map((rec) {
              final primary = rec.primary;
              final alts = rec.alternatives;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (primary != null)
                      Text('第一候補: $primary', style: theme.textTheme.bodyMedium),
                    if (alts.isNotEmpty)
                      Text(
                        '代替候補: ${alts.join('、')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (rec.condition != null &&
                        rec.condition!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '条件: ${rec.condition}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

GuideArtifactSlot? guideSlotFromArtifactSlotKey(ArtifactSlotKey slot) {
  switch (slot) {
    case ArtifactSlotKey.sands:
      return GuideArtifactSlot.sands;
    case ArtifactSlotKey.goblet:
      return GuideArtifactSlot.goblet;
    case ArtifactSlotKey.circlet:
      return GuideArtifactSlot.circlet;
    case ArtifactSlotKey.flower:
    case ArtifactSlotKey.plume:
      return null;
  }
}
