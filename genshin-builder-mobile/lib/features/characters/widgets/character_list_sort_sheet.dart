import 'package:flutter/material.dart';

import '../../../domain/character_list_sort.dart';

Future<void> showCharacterListSortSheet({
  required BuildContext context,
  required CharacterListSortSettings settings,
  required ValueChanged<CharacterListSortSettings> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      var current = settings;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          void apply(CharacterListSortSettings next) {
            setSheetState(() => current = next);
            onChanged(next);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '並び替え',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('所持 / 未所持でグループ分け'),
                    subtitle: Text(
                      current.mode == CharacterListSortMode.region
                          ? '地域並びではオフ（聖遺物一覧と同じ）'
                          : 'オフにすると1つのリストで並び替え',
                    ),
                    value: current.mode == CharacterListSortMode.region
                        ? false
                        : current.groupByOwnership,
                    onChanged: current.mode == CharacterListSortMode.region
                        ? null
                        : (value) =>
                            apply(current.copyWith(groupByOwnership: value)),
                  ),
                  const Divider(),
                  _SortSection(
                    title: '基本',
                    modes: const [
                      CharacterListSortMode.region,
                      CharacterListSortMode.ownedDefault,
                      CharacterListSortMode.nameAsc,
                      CharacterListSortMode.nameDesc,
                      CharacterListSortMode.rarityDesc,
                      CharacterListSortMode.rarityAsc,
                      CharacterListSortMode.element,
                    ],
                    selected: current.mode,
                    onSelected: (mode) => apply(current.copyWith(mode: mode)),
                  ),
                  const SizedBox(height: 8),
                  _SortSection(
                    title: '所持データ（HoYoLAB）',
                    subtitle:
                        '取得推定はアプリ導入後に新しく所持したキャラから記録されます',
                    modes: const [
                      CharacterListSortMode.levelDesc,
                      CharacterListSortMode.levelAsc,
                      CharacterListSortMode.obtainedDesc,
                      CharacterListSortMode.obtainedAsc,
                      CharacterListSortMode.constellationDesc,
                      CharacterListSortMode.friendshipDesc,
                    ],
                    selected: current.mode,
                    onSelected: (mode) => apply(current.copyWith(mode: mode)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _SortSection extends StatelessWidget {
  const _SortSection({
    required this.title,
    required this.modes,
    required this.selected,
    required this.onSelected,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<CharacterListSortMode> modes;
  final CharacterListSortMode selected;
  final ValueChanged<CharacterListSortMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        RadioGroup<CharacterListSortMode>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null) onSelected(value);
          },
          child: Column(
            children: [
              for (final mode in modes)
                RadioListTile<CharacterListSortMode>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(mode.label),
                  value: mode,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
