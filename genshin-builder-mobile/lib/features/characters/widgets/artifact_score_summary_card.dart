import 'package:flutter/material.dart';

import '../../../domain/artifact_score_weights.dart';
import '../../../domain/artifact_config.dart';
import '../../../domain/artifact_score.dart';
import '../../../domain/models/artifact_state.dart';
import '../../shared/game_icon_image.dart';

/// 5部位の聖遺物スコア合計 + 部位別内訳カード
class ArtifactScoreSummaryCard extends StatelessWidget {
  const ArtifactScoreSummaryCard({
    super.key,
    required this.artifacts,
    required this.scoreType,
    this.weights,
    this.scoreTypeLabel,
  });

  final ArtifactState artifacts;
  final ArtifactScoreType scoreType;
  final ArtifactStatWeights? weights;

  /// 表示用のスコア基準ラベル（例: "攻撃"）
  final String? scoreTypeLabel;

  double _pieceScore(ArtifactPiece piece) =>
      weights == null
          ? calcArtifactPieceScore(piece, scoreType)
          : calcArtifactPieceScoreWithWeights(piece, weights!);

  double _totalScore() =>
      weights == null
          ? calcArtifactTotalScore(artifacts, scoreType)
          : calcArtifactTotalScoreWithWeights(artifacts, weights!);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalScore();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              scoreTypeLabel == null
                  ? '聖遺物スコア合計'
                  : '聖遺物スコア合計（$scoreTypeLabel基準）',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              total.toStringAsFixed(1),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const Divider(height: 20),
            Text('内訳', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ...artifactSlotOrder.map((slot) {
              final piece = artifacts[slot] ?? createEmptyArtifactPiece();
              final label = artifactSlotLabels[slot] ?? slot.name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    GameIconImage(
                      iconUrl: piece.iconUrl,
                      size: 28,
                      fallback: Text(label, style: theme.textTheme.labelSmall),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(
                      child: Text(
                        piece.setName.isEmpty ? '-' : piece.setName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      _pieceScore(piece).toStringAsFixed(1),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
