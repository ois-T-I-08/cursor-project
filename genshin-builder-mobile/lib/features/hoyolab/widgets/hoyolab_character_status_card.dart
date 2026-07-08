import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/hoyolab_game_providers.dart';

class HoyolabCharacterStatusCard extends ConsumerWidget {
  const HoyolabCharacterStatusCard({
    super.key,
    required this.characterId,
  });

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildAsync = ref.watch(hoyolabCharacterBuildProvider(characterId));

    return buildAsync.when(
      data: (build) {
        if (build == null || !build.isOwned) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(
                alpha: 0.35,
              ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_sync),
                    const SizedBox(width: 8),
                    Text(
                      'HoYoLAB 実データ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _Chip(label: 'Lv.${build.level}'),
                    if (build.promoteLevel > 0)
                      _Chip(label: '突破 ${build.promoteLevel}'),
                    if (build.friendship > 0)
                      _Chip(label: '好感度 ${build.friendship}'),
                    if (build.constellation > 0)
                      _Chip(label: '凸 ${build.constellation}'),
                  ],
                ),
                if (build.stats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('ステータス', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  ...build.stats.take(8).map(
                        (s) => _StatLine(label: s.label, value: s.value),
                      ),
                ],
                if (build.talents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('天賦', style: Theme.of(context).textTheme.labelLarge),
                  ...build.talents.map(
                    (t) => _StatLine(label: t.name, value: 'Lv.${t.level}'),
                  ),
                ],
                if (build.weapon != null && build.weapon!.name.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('武器', style: Theme.of(context).textTheme.labelLarge),
                  _StatLine(
                    label: build.weapon!.name,
                    value:
                        'Lv.${build.weapon!.level} · R${build.weapon!.refinement}',
                  ),
                  if (build.weapon!.mainStat != null)
                    _StatLine(
                      label: 'メイン',
                      value: '${build.weapon!.mainStat!.label} ${build.weapon!.mainStat!.value}',
                    ),
                ],
                if (build.relics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('聖遺物', style: Theme.of(context).textTheme.labelLarge),
                  ...build.relics.map(
                    (r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatLine(
                          label: r.posName.isEmpty ? r.name : r.posName,
                          value: r.setName.isEmpty
                              ? '+${r.level}'
                              : '${r.setName} +${r.level}',
                        ),
                        if (r.mainStat != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              'メイン: ${r.mainStat!.label} ${r.mainStat!.value}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ...r.subStats.take(4).map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Text(
                                  'サブ: ${s.label} ${s.value}',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('HoYoLAB データを取得中…'),
            ],
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
