import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/amber_detail_models.dart';
import '../../../domain/artifact_score_weights.dart';
import '../../../domain/artifact_config.dart';
import '../../../domain/artifact_score.dart';
import '../../../domain/character_stats.dart';
import '../../../domain/models/artifact_state.dart';
import '../../../providers/build_recommendation_providers.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';
import 'guide_main_stats_panel.dart';

/// Artifact detail bottom sheet
Future<void> showArtifactDetailSheet({
  required BuildContext context,
  required String characterId,
  required ArtifactSlotKey slot,
  required ArtifactPiece piece,
  required ArtifactScoreType scoreType,
  ArtifactStatWeights? weights,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ArtifactDetailSheet(
        characterId: characterId,
        slot: slot,
        piece: piece,
        scoreType: scoreType,
        weights: weights,
        scrollController: scrollController,
      ),
    ),
  );
}

class ArtifactDetailSheet extends ConsumerWidget {
  const ArtifactDetailSheet({
    super.key,
    required this.characterId,
    required this.slot,
    required this.piece,
    required this.scoreType,
    this.weights,
    this.scrollController,
  });

  final String characterId;
  final ArtifactSlotKey slot;
  final ArtifactPiece piece;
  final ArtifactScoreType scoreType;
  final ArtifactStatWeights? weights;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setsAsync = ref.watch(artifactSetsProvider);
    final guideAsync = ref.watch(buildRecommendationProvider(characterId));
    ArtifactSetDetail? matched;
    for (final s in setsAsync.valueOrNull ?? const <ArtifactSetDetail>[]) {
      if (s.name == piece.setName) {
        matched = s;
        break;
      }
    }

    final theme = Theme.of(context);
    final slotLabel = artifactSlotLabels[slot] ?? slot.name;
    final score = weights == null
        ? calcArtifactPieceScore(piece, scoreType)
        : calcArtifactPieceScoreWithWeights(piece, weights!);
    final mainValue = piece.mainStat.isEmpty
        ? null
        : artifactMainStatValue(piece.mainStat, piece.level);
    final guideSlot = guideSlotFromArtifactSlotKey(slot);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            GameIconImage(
              iconUrl: piece.iconUrl ?? matched?.iconUrl,
              size: 56,
              fallback: Text(slotLabel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (piece.name != null && piece.name!.isNotEmpty)
                        ? piece.name!
                        : slotLabel,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (piece.setName.isNotEmpty)
                    Text(
                      piece.setName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _kv(theme, '部位', slotLabel),
        _kv(theme, 'レベル', '+${piece.level}'),
        if (piece.mainStat.isNotEmpty)
          _kv(
            theme,
            'メインステータス',
            mainValue == null
                ? piece.mainStat
                : '${piece.mainStat} ${_formatMain(piece.mainStat, mainValue)}',
          ),
        _kv(theme, '聖遺物スコア', score.toStringAsFixed(1)),
        if (guideSlot != null) ...[
          const SizedBox(height: 12),
          guideAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rec) {
              if (rec == null || rec.mainStats.isEmpty) {
                return const SizedBox.shrink();
              }
              final forSlot =
                  rec.mainStats.where((e) => e.slot == guideSlot).toList();
              if (forSlot.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '動画内メイン目安',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  GuideMainStatsPanel(
                    mainStats: forSlot,
                    freshnessCaption: rec.freshnessCaption,
                    compact: true,
                    filterSlot: guideSlot,
                  ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Text('サブステータス', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (piece.substats.isEmpty)
          Text(
            'サブステータス未入力',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...piece.substats.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.stat, style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    _formatSubstat(s.stat, s.value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 28),
        Text('セット効果', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (setsAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (matched == null || matched.effects.isEmpty)
          Text(
            piece.setName.isEmpty
                ? 'セット未設定'
                : 'セット効果を取得できませんでした',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...List.generate(matched.effects.length, (i) {
            final pieces = i == 0 ? 2 : (i == 1 ? 4 : (i + 1) * 2);
            final effect = matched!.effects[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$piecesセット効果',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(effect, style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  String _formatMain(String stat, double value) {
    if (stat.contains('%') ||
        stat.contains('会心') ||
        stat.contains('チャージ') ||
        stat.contains('ダメージ') ||
        stat.contains('治療')) {
      return '${value.toStringAsFixed(1)}%';
    }
    return value.round().toString();
  }

  String _formatSubstat(String stat, double value) {
    if (stat.contains('%') ||
        stat.contains('会心') ||
        stat.contains('チャージ') ||
        stat.contains('ダメージ') ||
        stat.contains('治療')) {
      return value == value.roundToDouble()
          ? '${value.toStringAsFixed(0)}%'
          : '${value.toStringAsFixed(1)}%';
    }
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}
