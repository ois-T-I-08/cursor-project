import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/artifact_config.dart';
import '../../../domain/models/artifact_state.dart';

/// 聖遺物セクション（API: セット・レベル / 手入力: メイン・サブステ）
class CharacterRelicsSection extends StatelessWidget {
  const CharacterRelicsSection({
    super.key,
    required this.artifacts,
    required this.onChanged,
  });

  final ArtifactState artifacts;
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
          'セット名・レベル・メインステータスは HoYoLAB 連携時に自動反映されます。サブステは手入力できます。',
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
              onMainStatChanged: (mainStat) =>
                  _updatePiece(slot, piece.copyWith(mainStat: mainStat)),
              onSubstatChanged: (index, stat, value) =>
                  _updateSubstat(slot, index, stat, value),
            ),
          );
        }),
      ],
    );
  }
}

class _PieceEditor extends StatelessWidget {
  const _PieceEditor({
    required this.slot,
    required this.piece,
    required this.onMainStatChanged,
    required this.onSubstatChanged,
  });

  final ArtifactSlotKey slot;
  final ArtifactPiece piece;
  final ValueChanged<String> onMainStatChanged;
  final void Function(int index, String stat, double value) onSubstatChanged;

  @override
  Widget build(BuildContext context) {
    final slotLabel = artifactSlotLabels[slot] ?? slot.name;
    final mainOptions = mainStatOptions[slot] ?? const [];
    final mainStatValue = _matchingOption(piece.mainStat, mainOptions);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  slotLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
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
              ],
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
    );
  }

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

String? _matchingOption(String value, List<String> options) {
  if (value.isEmpty) return null;
  return options.contains(value) ? value : null;
}
