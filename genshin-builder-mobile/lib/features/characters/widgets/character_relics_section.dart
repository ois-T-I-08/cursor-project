import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/artifact_score_weights.dart';
import '../../../domain/artifact_config.dart';
import '../../../domain/artifact_score.dart';
import '../../../domain/models/artifact_state.dart';
import '../../shared/game_icon_image.dart';
import 'artifact_detail_sheet.dart';

/// 聖遺物セクション（API: セット・レベル / 手入力: メイン・サブステ）
class CharacterRelicsSection extends StatelessWidget {
  const CharacterRelicsSection({
    super.key,
    required this.artifacts,
    required this.scoreType,
    this.resolvedScoreType,
    this.scoreTypeUserSet = false,
    this.weights,
    required this.onScoreTypeChanged,
    required this.onChanged,
  });

  final ArtifactState artifacts;
  final ArtifactScoreType scoreType;
  final ArtifactScoreType? resolvedScoreType;
  final bool scoreTypeUserSet;
  final ArtifactStatWeights? weights;
  final ValueChanged<ArtifactScoreType> onScoreTypeChanged;
  final ValueChanged<ArtifactState> onChanged;

  void _updatePiece(ArtifactSlotKey slot, ArtifactPiece piece) {
    onChanged(updateArtifactPiece(artifacts, slot, piece));
  }

  void _updateSubstat(
    ArtifactSlotKey slot,
    int index,
    String stat,
    double value,
  ) {
    final piece = artifacts[slot] ?? createEmptyArtifactPiece();
    final substats = List<ArtifactSubstat>.generate(
      4,
      (i) => i < piece.substats.length
          ? piece.substats[i]
          : const ArtifactSubstat(stat: '', value: 0),
    );
    substats[index] = ArtifactSubstat(stat: stat, value: value);
    _updatePiece(
      slot,
      piece.copyWith(
        substats: substats.where((s) => s.stat.isNotEmpty).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'セット名・レベル・メインステータスは HoYoLAB 連携時に自動反映されます。サブステは手入力できます。'
          '各部位を長押しすると詳細を表示します。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        ...artifactSlotOrder.map((slot) {
          final piece = artifacts[slot] ?? createEmptyArtifactPiece();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PieceEditor(
              slot: slot,
              piece: piece,
              scoreType: scoreType,
              weights: weights,
              onMainStatChanged: (mainStat) =>
                  _updatePiece(slot, piece.copyWith(mainStat: mainStat)),
              onSubstatChanged: (index, stat, value) =>
                  _updateSubstat(slot, index, stat, value),
              onLongPressDetail: () => showArtifactDetailSheet(
                context: context,
                slot: slot,
                piece: piece,
                scoreType: scoreType,
                weights: weights,
              ),
            ),
          );
        }),
        // スコア基準は画面最下部に配置する（合計スコアは画面上部のカードで表示）
        const Divider(height: 24),
        Text(
          'スコア基準: ${formatArtifactScoreTypeLabel(
            scoreType: scoreType,
            resolvedScoreType: resolvedScoreType,
            scoreTypeUserSet: scoreTypeUserSet,
          )}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (weights != null)
          Text(
            '重み: CR ${weights!.critRate} / CD ${weights!.critDamage} / '
            'ATK ${weights!.atkPercent} / HP ${weights!.hpPercent} / '
            'DEF ${weights!.defPercent} / ER ${weights!.energyRecharge} / '
            'EM ${weights!.elementalMastery}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ArtifactScoreType>(
          initialValue: scoreType,
          decoration: InputDecoration(
            labelText: _scoreTypeFieldLabel(
              resolvedScoreType: resolvedScoreType,
              scoreTypeUserSet: scoreTypeUserSet,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
          items: ArtifactScoreType.values
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(_scoreTypeLabel(type)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onScoreTypeChanged(value);
          },
        ),
      ],
    );
  }
}

/// アコーディオン概要: 部位アイコン + セット/レベルテキスト
class ArtifactSummaryContent extends StatelessWidget {
  const ArtifactSummaryContent({
    super.key,
    required this.artifacts,
    required this.scoreType,
    this.resolvedScoreType,
    this.scoreTypeUserSet = false,
    this.weights,
  });

  final ArtifactState artifacts;
  final ArtifactScoreType scoreType;
  final ArtifactScoreType? resolvedScoreType;
  final bool scoreTypeUserSet;
  final ArtifactStatWeights? weights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: artifactSlotOrder.map((slot) {
            final piece = artifacts[slot] ?? createEmptyArtifactPiece();
            final slotLabel = artifactSlotLabels[slot] ?? slot.name;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GameIconImage(
                iconUrl: piece.iconUrl,
                size: 36,
                fallback: Text(
                  slotLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          '合計スコア ${_formatScore(_calcTotalScore(artifacts, scoreType, weights))}'
          '（${formatArtifactScoreTypeLabel(
            scoreType: scoreType,
            resolvedScoreType: resolvedScoreType,
            scoreTypeUserSet: scoreTypeUserSet,
          )}）',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 2),
        Text(buildArtifactSummary(artifacts)),
      ],
    );
  }
}

class _PieceEditor extends StatelessWidget {
  const _PieceEditor({
    required this.slot,
    required this.piece,
    required this.scoreType,
    this.weights,
    required this.onMainStatChanged,
    required this.onSubstatChanged,
    required this.onLongPressDetail,
  });

  final ArtifactSlotKey slot;
  final ArtifactPiece piece;
  final ArtifactScoreType scoreType;
  final ArtifactStatWeights? weights;
  final ValueChanged<String> onMainStatChanged;
  final void Function(int index, String stat, double value) onSubstatChanged;
  final VoidCallback onLongPressDetail;

  @override
  Widget build(BuildContext context) {
    final slotLabel = artifactSlotLabels[slot] ?? slot.name;
    final mainOptions = mainStatOptions[slot] ?? const [];
    final mainStatValue = _matchingOption(piece.mainStat, mainOptions);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onLongPress: onLongPressDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GameIconImage(
                    iconUrl: piece.iconUrl,
                    size: 44,
                    fallback: Text(
                      slotLabel,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slotLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (piece.name != null && piece.name!.isNotEmpty)
                          Text(
                            piece.name!,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (piece.setName.isNotEmpty)
                    Flexible(
                      child: Text(
                        piece.setName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '+${piece.level}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  IconButton(
                    tooltip: '詳細',
                    icon: const Icon(Icons.info_outline, size: 20),
                    onPressed: onLongPressDetail,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'スコア ${_formatScore(_calcPieceScore(piece, scoreType, weights))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: mainStatValue,
                decoration: InputDecoration(
                  labelText: 'メインステータス',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
                items: mainOptions
                    .map(
                      (stat) => DropdownMenuItem(
                        value: stat,
                        child: Text(stat),
                      ),
                    )
                    .toList(),
                onChanged: (v) => onMainStatChanged(v ?? ''),
              ),
              const SizedBox(height: 8),
              ...List.generate(4, (i) {
                final sub = i < piece.substats.length
                    ? piece.substats[i]
                    : const ArtifactSubstat(stat: '', value: 0);
                final subStatValue = _matchingOption(sub.stat, subStatOptions);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: subStatValue,
                          decoration: InputDecoration(
                            labelText: 'サブ${i + 1}',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          items: subStatOptions
                              .map(
                                (stat) => DropdownMenuItem(
                                  value: stat,
                                  child: Text(stat),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              onSubstatChanged(i, v ?? '', sub.value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue:
                              sub.stat.isEmpty ? '' : _formatValue(sub.value),
                          enabled: sub.stat.isNotEmpty,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: '数値',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) => onSubstatChanged(
                            i,
                            sub.stat,
                            double.tryParse(v) ?? 0,
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
      ),
    );
  }

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

String _scoreTypeLabel(ArtifactScoreType type) => switch (type) {
      ArtifactScoreType.atk => '攻撃',
      ArtifactScoreType.def => '防御',
      ArtifactScoreType.hp => 'HP',
      ArtifactScoreType.recharge => '元素チャージ',
      ArtifactScoreType.em => '元素熟知',
    };

/// 手動変更時は「選択基準（取得基準）」形式で表示する。
String formatArtifactScoreTypeLabel({
  required ArtifactScoreType scoreType,
  ArtifactScoreType? resolvedScoreType,
  bool scoreTypeUserSet = false,
}) {
  final current = _scoreTypeLabel(scoreType);
  if (!scoreTypeUserSet ||
      resolvedScoreType == null ||
      resolvedScoreType == scoreType) {
    return current;
  }
  return '$current（${_scoreTypeLabel(resolvedScoreType)}）';
}

String _scoreTypeFieldLabel({
  required ArtifactScoreType? resolvedScoreType,
  required bool scoreTypeUserSet,
}) {
  if (!scoreTypeUserSet ||
      resolvedScoreType == null) {
    return 'スコア基準';
  }
  return 'スコア基準（${_scoreTypeLabel(resolvedScoreType)}）';
}

double _calcPieceScore(
  ArtifactPiece piece,
  ArtifactScoreType type,
  ArtifactStatWeights? weights,
) {
  if (weights == null) return calcArtifactPieceScore(piece, type);
  return calcArtifactPieceScoreWithWeights(piece, weights);
}

double _calcTotalScore(
  ArtifactState artifacts,
  ArtifactScoreType type,
  ArtifactStatWeights? weights,
) {
  if (weights == null) return calcArtifactTotalScore(artifacts, type);
  return calcArtifactTotalScoreWithWeights(artifacts, weights);
}

String _formatScore(double score) => score.toStringAsFixed(1);

String? _matchingOption(String value, List<String> options) {
  if (value.isEmpty) return null;
  return options.contains(value) ? value : null;
}
