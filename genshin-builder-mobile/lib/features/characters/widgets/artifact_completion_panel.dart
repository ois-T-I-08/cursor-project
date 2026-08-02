import 'package:flutter/material.dart';

import '../../../domain/artifact_completion.dart';
import '../../../domain/artifact_config.dart';
import '../../../domain/artifact_score.dart';
import '../../../domain/artifact_score_weights.dart';
import '../../../domain/models/artifact_state.dart';

/// 育成完了チェック + 部位別完成率バー。
class ArtifactCompletionPanel extends StatelessWidget {
  const ArtifactCompletionPanel({
    super.key,
    required this.artifacts,
    required this.scoreType,
    this.weights,
    required this.completed,
    required this.onCompletedChanged,
  });

  final ArtifactState artifacts;
  final ArtifactScoreType scoreType;
  final ArtifactStatWeights? weights;
  final bool completed;
  final ValueChanged<bool> onCompletedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = calcArtifactCompletionReport(
      artifacts,
      scoreType: scoreType,
      weights: weights,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: completed,
          onChanged: (v) => onCompletedChanged(v ?? false),
          title: const Text('育成完了'),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
        Text(
          '完成率：${report.overallPercent.round()}%',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final slot in artifactSlotOrder) ...[
          _SlotCompletionBar(
            label: artifactSlotLabels[slot] ?? slot.name,
            percent: report.bySlot[slot] ?? 0,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _SlotCompletionBar extends StatelessWidget {
  const _SlotCompletionBar({required this.label, required this.percent});

  final String label;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (percent / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${percent.round()}%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
