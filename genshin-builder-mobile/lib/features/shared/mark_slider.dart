import 'package:flutter/material.dart';

import '../../domain/level_config.dart';

/// 目盛りスナップ付きスライダー（Web MarkSlider 相当）
class MarkSlider extends StatelessWidget {
  const MarkSlider({
    super.key,
    required this.label,
    required this.value,
    required this.marks,
    required this.max,
    required this.onChanged,
    this.headerTrailing,
  });

  final String label;
  final int value;
  final List<int> marks;
  final int max;
  final ValueChanged<int> onChanged;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final markIndex = marks.indexOf(value).clamp(0, marks.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('Lv.$value'),
            if (headerTrailing != null) ...[
              const SizedBox(width: 8),
              headerTrailing!,
            ],
          ],
        ),
        Slider(
          value: markIndex.toDouble(),
          min: 0,
          max: (marks.length - 1).toDouble(),
          divisions: marks.length - 1,
          label: 'Lv.$value',
          onChanged: (v) => onChanged(marks[v.round()]),
        ),
        Wrap(
          spacing: 8,
          children:
              marks
                  .where((m) => m <= max)
                  .map(
                    (m) => ChoiceChip(
                      label: Text('$m'),
                      selected: m == value,
                      onSelected: (_) => onChanged(m),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

/// キャラ Lv 用ショートカット
class LevelMarkSlider extends StatelessWidget {
  const LevelMarkSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.headerTrailing,
    this.label = 'レベル',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final Widget? headerTrailing;
  final String label;

  @override
  Widget build(BuildContext context) {
    return MarkSlider(
      label: label,
      value: value,
      marks: levelMarksList,
      max: levelMax,
      onChanged: onChanged,
      headerTrailing: headerTrailing,
    );
  }
}
